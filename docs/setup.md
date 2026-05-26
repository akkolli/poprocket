# Setup

## Bridge

The bridge runs inside the homelab and owns access to Docker, WOL broadcast, Uptime Kuma, REST endpoints, and future adapters. Start from the example config:

```sh
cp configs/bridge.example.yaml bridge.yaml
docker compose up --build
```

For production, mount a writable data directory and keep `relay.token` private. The bridge writes audit history to SQLite at `bridge.data_path`.

## Pairing

Create a one-time pairing payload:

```sh
curl -X POST http://bridge.local:8080/v1/pairing/start
```

The response contains a `qr_payload` string. The iOS app scans that QR, stores bridge credentials in Keychain, registers its APNs token with the relay, and refreshes dashboard cards.

The QR payload contains:

- bridge ID and display name
- relay HTTP/WebSocket URL
- one-time pairing token
- bridge public key
- direct LAN/Tailscale URLs

## Notifications

Scripts send events to the bridge:

```sh
curl -X POST http://bridge.local:8080/v1/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Job failed","body":"A monitored job exited 2","severity":"warning"}'
```

The bridge records the event, creates an opaque relay envelope, and asks the relay to fan out APNs pushes.

## Widgets

Widgets do not poll the bridge live. The iOS app updates an App Group cache during foreground refreshes, notification wakeups, and App Intent actions. Widget views render the cached cards with a clear freshness state.
