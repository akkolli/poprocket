# API Contract

All timestamps are RFC3339 UTC. Backend routes are platform neutral so Android can later use the same contracts with Kotlin, Glance widgets, FCM, and direct reply actions.

Sensitive bridge reads use signed request headers after pairing:

- `X-PopRocket-Device-ID`
- `X-PopRocket-Created-At`
- `X-PopRocket-Signature`

The canonical signed request includes HTTP method, path, optional raw query, actor device ID, and created-at timestamp. Signed reads and action envelopes must be created within five minutes of the bridge clock.

## Bridge

### `GET /v1/health`

Returns bridge identity, relay connectivity state, clock time, uptime, and coarse feature capabilities such as whether the command runner and ad-hoc command execution are enabled.

### `POST /v1/pairing/start`

Creates a one-time QR payload. When `security.pairing_access_token` is configured, callers must send it as a bearer token; the installer enables this protection by default.

### `POST /v1/pairing/complete`

Registers a device public key after the app presents a valid one-time token. Requested scopes are intersected with `security.default_scopes`; the response returns the scopes actually granted and an optional `relay_access_token` for Keychain storage.

### `GET /v1/cards`

Returns legacy status snapshots for widgets and configured external readers. The paired device must sign the request and have `cards:read`. The iOS app presents these as status data, while saved user commands are called action tiles.

### `GET /v1/monitors`

Returns bridge-side health checks for configured, user-created, and WOL-derived monitors. The paired device must sign the request and have `monitor:read`. Each monitor includes current status, response time, last checked time, and the time when its current status began.

### `POST /v1/monitors`

Creates a user-managed health monitor. Supported kinds are `tcp` and `http`. The request body is a signed action envelope with action id `monitor:create`; editable fields are carried in signed `parameters`, and the paired device must have `monitor:write`.

```json
{
  "action_run_id": "run_...",
  "action_id": "monitor:create",
  "actor_device_id": "iphone",
  "confirmed": true,
  "parameters": {
    "id": "mon_server_ssh",
    "name": "Server SSH",
    "kind": "tcp",
    "host": "server",
    "port": "22",
    "timeout_seconds": "3"
  },
  "created_at": "2026-05-28T10:00:00Z",
  "signature": "..."
}
```

### `PUT /v1/monitors/{monitor_id}`

Updates a user-managed health monitor with a signed `monitor:update` envelope. The signed `parameters.id` must match the path id. Monitors sourced from bridge config or WOL targets are read-only through the API.

### `DELETE /v1/monitors/{monitor_id}`

Deletes a user-managed health monitor with a signed `monitor:delete` envelope. The signed `parameters.id` must match the path id.

### `POST /v1/notify`

Accepts a homelab event. When `security.notification_token` is configured, callers must send `Authorization: Bearer <token>`.

```json
{
  "event_id": "evt_...",
  "severity": "warning",
  "title": "Job failed",
  "body": "A monitored job exited with status 2",
  "source": "cron/example",
  "actions": [
    {"id": "ack", "title": "Ack", "kind": "audit"}
  ],
  "card_ids": [],
  "ttl_seconds": 900,
  "created_at": "2026-05-25T13:00:00Z",
  "idempotency_key": "job-example-2026-05-25"
}
```

The bridge derives short APNs display text from `title` and `body` before forwarding the event to the relay. Use concise, non-secret copy because APNs display text is visible to Apple notification infrastructure. Fireman should set `source` to a value beginning with `fireman`, for example `fireman/api-service`, so PopRocket can use security-alert fallback copy when `title` or `body` are omitted.

### `POST /v1/actions/{action_run_id}`

Receives a signed action envelope from the app or relay. The bridge validates device scope, signature, idempotency, five-minute freshness, and confirmation policy before execution.

Ad-hoc command execution uses action id `command:run` and signs the command text inside `parameters`:

```json
{
  "action_run_id": "run_...",
  "action_id": "command:run",
  "actor_device_id": "iphone",
  "confirmed": true,
  "parameters": {
    "command": "ssh user@server wake desktop"
  },
  "created_at": "2026-05-26T13:00:00Z",
  "signature": "..."
}
```

The bridge only accepts this when `command_runner.enabled` and `command_runner.allow_ad_hoc` are true, and the paired device has the `command:run` scope.

### `GET /v1/audit`

Returns action audit records. The paired device must sign the request and have `audit:read`.

### `POST /v1/wol/{target_id}/wake`

Sends a WOL magic packet from inside the homelab and records an audit entry. The request body is a signed action envelope with action id `wol:{target_id}`, which requires `wol:wake:{target_id}` or `wol:wake:*`.

### `POST /v1/wol-targets`

Creates a user-managed Wake-on-LAN target with a signed `wol-target:create` envelope and the `wol:manage` scope. The signed parameters include `id`, `name`, `mac`, and either `broadcast_ip` or `ip_address`.

### `GET /v1/wol-targets`

Returns configured and user-managed Wake-on-LAN targets. The paired device must sign the request and have `wol:read`.

### `PUT /v1/wol-targets/{target_id}`

Updates a user-managed Wake-on-LAN target with a signed `wol-target:update` envelope. Config-backed targets are read-only.

### `DELETE /v1/wol-targets/{target_id}`

Deletes a user-managed Wake-on-LAN target with a signed `wol-target:delete` envelope.

## Relay

All relay endpoints except `GET /v1/health` require bearer authentication, and JSON request bodies are limited to 128 KiB. Bridge push/WebSocket calls use `relay.token`; device registration and fallback actions use the bridge-scoped `relay_access_token` returned after pairing.

### `POST /v1/devices/register`

Registers an iOS APNs token for a bridge/device pair.

### `POST /v1/push`

Receives an opaque event reference from a bridge and fans out APNs pushes. The relay must not receive API secrets, plaintext homelab credentials, or action request bodies. The reference is deliberately non-reversible, but it is not a substitute for a future end-to-end encrypted notification envelope.

### `POST /v1/actions`

Accepts an opaque action envelope from a device and delivers it to the bridge over the bridge's outbound WebSocket when direct bridge access is unavailable.

### `GET /v1/ws/bridge`

Bridge outbound WebSocket used for relay-to-bridge action delivery and bridge health pings.
