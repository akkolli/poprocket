#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bridge_host="${1:-}"
if [[ -z "$bridge_host" ]]; then
  if command -v hostname >/dev/null 2>&1; then
    bridge_host="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
fi

if [[ -z "$bridge_host" ]]; then
  echo "Usage: ./scripts/bridge_install.sh <bridge-ip-or-hostname> [bridge-name]" >&2
  exit 2
fi

safe_bridge_id() {
  local raw="$1"
  local safe
  safe="$(printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  if [[ -z "$safe" ]]; then
    safe="local"
  fi
  printf 'bridge-%s' "$safe"
}

normalize_bridge_name() {
  local raw="$1"
  # Earlier hardware-specific bridge names are accepted only so older installs
  # migrate into the generic bridge naming model without forcing a fresh pairing.
  case "$raw" in
    ""|"PopRocket Pi Bridge"|"PopRocket Bridge")
      printf 'Local Bridge'
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return
  fi
  od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]'
}

bridge_id="${POPROCKET_BRIDGE_ID:-$(safe_bridge_id "$bridge_host")}"
if [[ "$bridge_id" == "poprocket-pi" ]]; then
  bridge_id="$(safe_bridge_id "$bridge_host")"
fi
bridge_name="$(normalize_bridge_name "${POPROCKET_BRIDGE_NAME:-${2:-Local Bridge}}")"
pairing_access_token="${POPROCKET_PAIRING_ACCESS_TOKEN:-$(generate_secret)}"
notification_token="${POPROCKET_NOTIFICATION_TOKEN:-$(generate_secret)}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required on the bridge host before running this script" >&2
  exit 1
fi

compose=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose)
  else
    echo "docker compose or docker-compose is required on the bridge host" >&2
    exit 1
  fi
fi

mkdir -p deploy/bridge/local
bridge_config="deploy/bridge/local/bridge.yaml"
# Older installers wrote the local config under a legacy host-specific path. Read
# it once and carry it forward into deploy/bridge so new installs stay general.
legacy_bridge_config="deploy/pi/local/bridge.yaml"
if [[ ! -f "$bridge_config" ]]; then
  if [[ -f "$legacy_bridge_config" ]]; then
    cp "$legacy_bridge_config" "$bridge_config"
    echo "Migrated existing bridge config to $bridge_config"
  else
    sed \
      -e "s|{{BRIDGE_ID}}|$bridge_id|g" \
      -e "s|{{BRIDGE_HOST}}|$bridge_host|g" \
      -e "s|{{BRIDGE_NAME}}|$bridge_name|g" \
      -e "s|{{PAIRING_ACCESS_TOKEN}}|$pairing_access_token|g" \
      -e "s|{{NOTIFICATION_TOKEN}}|$notification_token|g" \
      deploy/bridge/bridge.yaml.template > "$bridge_config"
  fi
else
  echo "Using existing $bridge_config"
fi

tmp_config="${bridge_config}.tmp"
awk -v bridge_id="$bridge_id" -v bridge_host="$bridge_host" -v bridge_name="$bridge_name" '
BEGIN { in_bridge = 0; in_direct_urls = 0; replaced_legacy_direct_urls = 0; migrated = 0 }
/^bridge:/ {
  in_bridge = 1
  print
  next
}
in_bridge && /^[^[:space:]]/ {
  in_bridge = 0
  in_direct_urls = 0
}
in_bridge && /^[[:space:]]+id:[[:space:]]*["'\'']?poprocket-pi["'\'']?[[:space:]]*$/ {
  print "  id: \"" bridge_id "\""
  migrated = 1
  next
}
in_bridge && /^[[:space:]]+name:[[:space:]]*["'\'']?(PopRocket Pi Bridge|PopRocket Bridge)["'\'']?[[:space:]]*$/ {
  print "  name: \"" bridge_name "\""
  migrated = 1
  next
}
in_bridge && /^[[:space:]]+public_url:/ && ($0 ~ /poprocket-pi/ || $0 ~ /poprocket-bridge/ || $0 ~ /:8080/) {
  print "  public_url: \"http://" bridge_host ":6567\""
  migrated = 1
  next
}
in_bridge && /^[[:space:]]+direct_urls:/ {
  in_direct_urls = 1
  print
  next
}
in_direct_urls && /^[[:space:]]+-/ && ($0 ~ /poprocket-pi/ || $0 ~ /poprocket-bridge/ || $0 ~ /:8080/) {
  if (!replaced_legacy_direct_urls) {
    print "    - \"http://" bridge_host ":6567\""
    print "    - \"http://bridge.local:6567\""
    replaced_legacy_direct_urls = 1
    migrated = 1
  }
  next
}
{ print }
END {
  if (migrated) {
    print "# legacy bridge defaults were migrated by scripts/bridge_install.sh" > "/dev/stderr"
  }
}
' "$bridge_config" > "$tmp_config"
mv "$tmp_config" "$bridge_config"

if ! grep -q '^security:[[:space:]]*$' "$bridge_config"; then
  {
    printf '\nsecurity:\n'
    printf '  pairing_ttl_seconds: 300\n'
    printf '  pairing_access_token: "%s"\n' "$pairing_access_token"
    printf '  notification_token: "%s"\n' "$notification_token"
    printf '  default_scopes:\n'
  } >> "$bridge_config"
fi

if ! grep -q '^[[:space:]]*pairing_access_token:' "$bridge_config"; then
  tmp_config="${bridge_config}.tmp"
  awk -v token="$pairing_access_token" '
  /^security:[[:space:]]*$/ && !inserted {
    print
    print "  pairing_access_token: \"" token "\""
    inserted = 1
    next
  }
  { print }
  ' "$bridge_config" > "$tmp_config"
  mv "$tmp_config" "$bridge_config"
fi

if ! grep -q '^[[:space:]]*notification_token:' "$bridge_config"; then
  tmp_config="${bridge_config}.tmp"
  awk -v token="$notification_token" '
  /^security:[[:space:]]*$/ && !inserted {
    print
    print "  notification_token: \"" token "\""
    inserted = 1
    next
  }
  { print }
  ' "$bridge_config" > "$tmp_config"
  mv "$tmp_config" "$bridge_config"
fi
pairing_access_token="$(awk '/^[[:space:]]*pairing_access_token:/ { value = $2; gsub(/["'\'']/, "", value); print value; exit }' "$bridge_config")"
chmod 600 "$bridge_config"

ensure_scope() {
  local scope="$1"
  if grep -F -q "    - \"$scope\"" "$bridge_config"; then
    return
  fi

  tmp_config="${bridge_config}.tmp"
  awk -v scope="$scope" '
  {
    if (in_default_scopes && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[^[:space:]]/)) {
      print "    - \"" scope "\""
      inserted = 1
      in_default_scopes = 0
    }
    print
    if (!inserted && $0 ~ /^[[:space:]]+default_scopes:[[:space:]]*$/) {
      in_default_scopes = 1
    }
  }
  END {
    if (in_default_scopes && !inserted) {
      print "    - \"" scope "\""
    }
  }
  ' "$bridge_config" > "$tmp_config"
  mv "$tmp_config" "$bridge_config"
}

ensure_scope "cards:read"
ensure_scope "audit:read"
ensure_scope "notify:receive"
ensure_scope "monitor:read"
ensure_scope "monitor:write"
ensure_scope "wol:read"
ensure_scope "wol:manage"
ensure_scope "wol:wake:*"

export POPROCKET_COMPOSE_PROJECT="${POPROCKET_COMPOSE_PROJECT:-poprocket-bridge}"
export POPROCKET_BRIDGE_CONTAINER="${POPROCKET_BRIDGE_CONTAINER:-poprocket-bridge}"
export POPROCKET_BRIDGE_VOLUME="${POPROCKET_BRIDGE_VOLUME:-poprocket-bridge-data}"
export POPROCKET_BRIDGE_CONFIG_VOLUME="${POPROCKET_BRIDGE_CONFIG_VOLUME:-poprocket-bridge-config}"

# Remove the old compose-generated container name if it exists so the generic
# container can start cleanly on hosts that used the previous installer.
legacy_container="pi-bridge-1"
if docker container inspect "$legacy_container" >/dev/null 2>&1; then
  echo "Removing legacy bridge container from an older installer"
  docker rm -f "$legacy_container" >/dev/null
fi

if ! grep -q '^command_runner:[[:space:]]*$' "$bridge_config"; then
  {
    printf '\ncommand_runner:\n'
    printf '  enabled: false\n'
    printf '  allow_ad_hoc: false\n'
    printf '  allow_shell_operators: false\n'
    printf '  shell: "/bin/sh"\n'
    printf '  timeout_seconds: 30\n'
    printf '  max_output_bytes: 4096\n'
    printf '  allowed_prefixes: []\n'
  } >> "$bridge_config"
fi

if grep -q '^[[:space:]]*allow_ad_hoc:[[:space:]]*true[[:space:]]*$' "$bridge_config" \
  && grep -q '^[[:space:]]*allowed_prefixes:[[:space:]]*\[\][[:space:]]*$' "$bridge_config"; then
  tmp_config="${bridge_config}.tmp"
  sed 's/^[[:space:]]*allow_ad_hoc:[[:space:]]*true[[:space:]]*$/  allow_ad_hoc: false/' "$bridge_config" > "$tmp_config"
  mv "$tmp_config" "$bridge_config"
  chmod 600 "$bridge_config"
  echo "Disabled unsafe ad-hoc commands because no command allowlist was configured."
fi

"${compose[@]}" -f deploy/bridge/compose.yaml up --build -d

echo "PopRocket bridge is running at http://$bridge_host:6567"
echo "In the iOS app, pair manually with http://$bridge_host:6567"
echo "Pairing code: $pairing_access_token"
