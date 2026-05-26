# PopRocket

PopRocket is an iOS-first homelab operations control plane. It pairs a native iOS app with a self-hosted bridge and an opaque hosted relay so homelab scripts can send actionable notifications, widgets can show cached status, and every privileged action is scoped and audited.

This repository is organized as a monorepo:

- `apps/ios` - SwiftUI app source, WidgetKit widget, App Intents, notification handling, Keychain, and App Group cache helpers.
- `services/bridge` - Go bridge service that runs inside the homelab, owns secrets, sends WOL packets, runs explicitly enabled shell commands, exposes cards/actions, stores SQLite audit history, and connects outbound to the relay.
- `services/relay` - Go relay service for APNs fanout and encrypted bridge/device action delivery. Relay payloads are intentionally opaque.
- `docs` - setup guide, API contract, threat model, and template examples.
- `configs` - starter bridge config and reusable templates.

## Quick Start

```sh
docker compose up --build -d
```

The local compose stack starts the bridge, relay, and a fake Uptime Kuma endpoint for fresh sample card data.

For a Raspberry Pi bridge that can send Wake-on-LAN packets from your LAN, see [`docs/pi.md`](docs/pi.md):

```sh
./scripts/pi_install.sh 192.168.0.25
```

Create a pairing QR from the bridge:

```sh
curl -X POST http://localhost:8080/v1/pairing/start
```

For a screenless Raspberry Pi bridge, use the iOS app's manual pairing field with `http://<bridge-ip>:6567`; no QR display is required.

Send an actionable notification:

```sh
curl -X POST http://localhost:8080/v1/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "severity": "warning",
    "title": "Job failed",
    "body": "A monitored job exited with status 2",
    "source": "cron/example",
    "actions": [
      {"id": "ack", "title": "Ack", "kind": "audit"}
    ],
    "card_ids": [],
    "ttl_seconds": 900,
    "idempotency_key": "job-example-2026-05-25"
  }'
```

## Local Verification

```sh
./scripts/verify_structure.sh
```

When Go and Docker are installed:

```sh
make test
make docker-build
docker compose config
```

When Xcode is installed:

```sh
swift test --package-path apps/ios
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
xcodebuild test -quiet -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'platform=iOS Simulator,name=iPhone 17'
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
curl -fsS 'http://localhost:8080/v1/audit?limit=5' | jq .
```

## Design Constraints

The relay never stores homelab API secrets or plaintext action payloads. The bridge owns integrations, action policy, idempotency, and audit writes. iOS widgets read a shared App Group cache and always show freshness because widgets are not live dashboards.
