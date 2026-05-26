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
sed "s|{{PI_HOST}}|$pi_host|g" deploy/pi/bridge.yaml.template > deploy/pi/local/bridge.yaml

"${compose[@]}" -f deploy/pi/compose.yaml up --build -d

echo "PopRocket bridge is running at http://$pi_host:6567"
echo "In the iOS app, pair manually with http://$pi_host:6567"
