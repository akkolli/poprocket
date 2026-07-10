# Fireman Notifications

Fireman can send dependency security alerts through the existing PopRocket bridge notification route. The bridge stores the full event, sends a short display alert to the relay for APNs, and keeps the signed action/audit model unchanged.

Use `source` values that start with `fireman` so PopRocket can apply Fireman-specific fallback copy when a title or body is omitted.

```sh
curl -X POST "$POPROCKET_BRIDGE_URL/v1/notify" \
  -H 'Content-Type: application/json' \
  -d '{
    "severity": "critical",
    "title": "Dependency security issue",
    "body": "Fireman found vulnerable dependencies in api-service",
    "source": "fireman/api-service",
    "actions": [
      {"id": "ack", "title": "Ack", "kind": "audit"}
    ],
    "ttl_seconds": 3600,
    "idempotency_key": "fireman-api-service-2026-06-14"
  }'
```

Delivery path:

- Fireman posts to the trusted LAN bridge.
- The bridge records the event and asks the relay to fan out an APNs alert.
- The iPhone receives the push after pairing and APNs registration.
- Apple Watch receives the same important alert through iPhone notification mirroring.

Keep APNs display text short and avoid secrets. Detailed vulnerability metadata should stay in Fireman or the bridge event body, not in notification titles.
