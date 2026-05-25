# API Contract

All timestamps are RFC3339 UTC. Backend routes are platform neutral so Android can later use the same contracts with Kotlin, Glance widgets, FCM, and direct reply actions.

## Bridge

### `GET /v1/health`

Returns bridge identity, relay connectivity state, and clock time.

### `POST /v1/pairing/start`

Creates a one-time QR payload.

### `POST /v1/pairing/complete`

Registers a device public key and scoped credentials after the app scans a valid QR token.

### `GET /v1/cards`

Returns card snapshots. Values may be fresh, stale, or error.

### `POST /v1/notify`

Accepts a homelab event.

```json
{
  "event_id": "evt_...",
  "severity": "warning",
  "title": "Backup failed",
  "body": "nas01 backup exited 2",
  "source": "cron/nas01",
  "actions": [
    {"id": "ack", "title": "Ack", "kind": "audit"},
    {"id": "wake_nas", "title": "Wake NAS", "kind": "wol", "scope": "wol:wake:nas01"}
  ],
  "card_ids": ["bridge_host"],
  "ttl_seconds": 900,
  "created_at": "2026-05-25T13:00:00Z",
  "idempotency_key": "backup-nas01-2026-05-25"
}
```

### `POST /v1/actions/{action_run_id}`

Receives a signed action envelope from the app or relay. The bridge validates device scope, signature, idempotency, expiration, and confirmation policy before execution.

### `GET /v1/audit`

Returns action audit records.

### `POST /v1/wol/{target_id}/wake`

Sends a WOL magic packet from inside the homelab and records an audit entry.

## Relay

### `POST /v1/devices/register`

Registers a device token for a bridge/device pair.

### `POST /v1/push`

Receives an opaque encrypted envelope from a bridge and fans out APNs pushes. The relay must not receive API secrets or plaintext homelab credentials.

### `POST /v1/actions`

Accepts an opaque action envelope from a device and delivers it to the bridge over the bridge's outbound WebSocket when direct bridge access is unavailable.

### `GET /v1/ws/bridge`

Bridge outbound WebSocket used for relay-to-bridge action delivery and bridge health pings.
