#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pi_host="${1:-}"
if [[ -z "$pi_host" ]]; then
  if command -v hostname >/dev/null 2>&1; then
    pi_host="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
fi

if [[ -z "$pi_host" ]]; then
  echo "Usage: ./scripts/pi_install.sh <pi-ip-or-hostname>" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required on the Pi before running this script" >&2
  exit 1
fi

compose=(docker compose)
if ! docker compose version >/dev/null 2>&1; then
  if command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose)
  else
    echo "docker compose or docker-compose is required on the Pi" >&2
    exit 1
  fi
fi

mkdir -p deploy/pi/local
bridge_config="deploy/pi/local/bridge.yaml"
if [[ ! -f "$bridge_config" ]]; then
  sed "s|{{PI_HOST}}|$pi_host|g" deploy/pi/bridge.yaml.template > "$bridge_config"
else
  echo "Using existing $bridge_config"
fi

if ! grep -q '^[[:space:]]*- "command:run"' "$bridge_config"; then
  tmp_config="${bridge_config}.tmp"
  awk '
  {
    print
    if ($0 ~ /^[[:space:]]*- "wol:wake:\*"$/) {
      print "    - \"command:run\""
    }
  }
  ' "$bridge_config" > "$tmp_config"
  mv "$tmp_config" "$bridge_config"
fi

tmp_config="${bridge_config}.tmp"
awk '
function print_command_runner() {
  print "command_runner:"
  print "  enabled: true"
  print "  allow_ad_hoc: true"
  print "  shell: \"/bin/sh\""
  print "  timeout_seconds: 30"
  print "  max_output_bytes: 4096"
  print "  allowed_prefixes:"
  print "    - \"ssh lepton@pluto \""
  print "    - \"ssh -o BatchMode=yes -o ConnectTimeout=5 lepton@pluto \""
}
BEGIN { in_command_runner = 0; saw_command_runner = 0 }
/^command_runner:/ {
  print_command_runner()
  in_command_runner = 1
  saw_command_runner = 1
  next
}
in_command_runner && /^[^[:space:]]/ {
  in_command_runner = 0
}
!in_command_runner {
  print
}
END {
  if (!saw_command_runner) {
    print ""
    print_command_runner()
  }
}
' "$bridge_config" > "$tmp_config"
mv "$tmp_config" "$bridge_config"

"${compose[@]}" -f deploy/pi/compose.yaml up --build -d

echo "PopRocket bridge is running at http://$pi_host:6567"
echo "In the iOS app, pair manually with http://$pi_host:6567"
