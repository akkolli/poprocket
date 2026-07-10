# Setup

## Bridge

The bridge runs inside the homelab and owns access to Docker, WOL broadcast, Uptime Kuma, REST endpoints, and future adapters. Start from the example config:

```sh
cp configs/bridge.example.yaml bridge.yaml
docker compose up --build
```

For production, mount a writable data directory and keep `relay.token` and `security.notification_token` private. The bridge writes audit history to SQLite at `bridge.data_path`. The installer generates a notification token and stores the resulting config with owner-only permissions.

Set `POPROCKET_RELAY_DATA_PATH` to a writable file path so APNs device registrations survive relay restarts. The development Compose stack enables this at `/var/lib/poprocket/relay-state.json` with owner-only state-file permissions.

## Pairing

Create a one-time pairing payload:

```sh
curl -X POST http://bridge.local:6567/v1/pairing/start \
  -H 'Authorization: Bearer <security.pairing_access_token>'
```

The response contains a `qr_payload` string. The iOS app scans that QR, stores bridge credentials in Keychain, registers its APNs token with the relay, and refreshes bridge status, monitors, actions, and WOL targets. For manual setup, enter the pairing code printed by `bridge_install.sh`; starting a pairing session is otherwise denied on new installations.

Bridge reads and management operations are signed after pairing. Use bridge scopes such as `cards:read`, `audit:read`, `monitor:read`, `monitor:write`, `wol:read`, `wol:manage`, `wol:wake:*`, and `command:run` for the app features you want enabled. After changing bridge scopes, use Bridge Settings > reconnect in the iOS app to refresh the stored pairing.

The QR payload contains:

- bridge ID and display name
- relay HTTP/WebSocket URL
- one-time pairing token
- bridge public key
- direct LAN/Tailscale URLs

## Notifications

Scripts send events to the bridge:

```sh
curl -X POST http://bridge.local:6567/v1/notify \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <security.notification_token>' \
  -d '{"title":"Job failed","body":"A monitored job exited 2","severity":"warning"}'
```

The bridge authenticates the notification token, records the event, creates an opaque relay envelope, and asks the relay to fan out APNs pushes with a short display title/body. After the iPhone app is paired and notification permission is granted, it registers its APNs token with the relay using relay access stored in Keychain. Apple Watch receives these important alerts through iPhone notification mirroring, and the watchOS app shows the latest synced bridge status from the phone.

Fireman dependency security alerts should use `source` values that start with `fireman`; see [`fireman.md`](fireman.md).

For real APNs delivery, run the relay with token mode and mount the Apple `.p8` provider key read-only:

```sh
POPROCKET_APNS_MODE=token
POPROCKET_APNS_TEAM_ID=<apple-team-id>
POPROCKET_APNS_KEY_ID=<provider-key-id>
POPROCKET_APNS_TOPIC=com.poprocket.app
POPROCKET_APNS_PRIVATE_KEY_PATH=/run/secrets/AuthKey.p8
POPROCKET_APNS_SANDBOX=false
```

Use sandbox mode only with development APNs device tokens. Log mode remains available for local development and never contacts Apple.

## Widgets

Widgets do not poll the bridge live. The iOS app updates an App Group cache during foreground refreshes, notification wakeups, and App Intent actions. Widget views render cached status snapshots with a clear freshness state and request a five-minute WidgetKit timeline cadence, subject to iOS scheduling.
