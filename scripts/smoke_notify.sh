#!/usr/bin/env sh
set -eu

bridge_url="${1:-http://localhost:6567}"

curl -sS -X POST "$bridge_url/v1/notify" \
  -H 'Content-Type: application/json' \
  -d '{
    "severity": "info",
    "title": "PopRocket smoke test",
    "body": "Notification path is reachable",
    "source": "scripts/smoke_notify.sh",
    "actions": [{"id":"ack","title":"Ack","kind":"audit"}],
    "ttl_seconds": 300,
    "idempotency_key": "smoke-test"
  }'
