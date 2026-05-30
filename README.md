# PopRocket

PopRocket is a native iPhone control surface for a private homelab. It pairs a polished SwiftUI app with a trusted bridge running inside your LAN so the phone can monitor devices and services, wake machines, run SSH or shell commands, save common commands as reusable action tiles, and manage multiple bridges without exposing internal systems directly to the internet.

The bridge is the local authority. It owns SSH keys and LAN access, sends Wake-on-LAN packets, performs TCP/HTTP health checks, stores monitor state and action audit history in SQLite, and exposes a narrow API to paired devices. The iPhone never needs broad network access or SSH credentials; it asks the bridge to perform scoped operations and displays the result.

This repository is organized as a monorepo:

- `apps/ios` - SwiftUI app source, WidgetKit widget, App Intents, notification handling, Keychain, and App Group cache helpers.
- `services/bridge` - Go bridge service that runs inside the homelab, owns secrets, sends WOL packets, runs explicitly enabled shell commands, checks monitor health, exposes status snapshots/actions, stores SQLite state and audit history, and connects outbound to the relay.
- `services/relay` - Go relay service for APNs fanout and encrypted bridge/device action delivery. Relay payloads are intentionally opaque.
- `docs` - setup guide, API contract, threat model, and template examples.
- `configs` - starter bridge config and reusable templates.

## Current App Surface

- Bridge status/settings: see bridge reachability and uptime, pair by QR or URL, name bridges, switch active bridge, reconnect an existing bridge to refresh scopes, and remove old bridges.
- Health: add TCP/HTTP monitors through signed bridge management requests, see up/down state, response time, last check time, current up/down duration, and timestamped last-known health after app relaunches or bridge outages.
- Commands: run ad-hoc bridge commands, save frequent commands as named bridge-scoped action tiles, see each tile's last run status, edit/delete tiles, and see command output.
- Wake-on-LAN: add devices through signed bridge management requests, derive broadcast addresses from device IPs, wake devices with visible sent/failed feedback, and auto-create SSH health checks for WOL targets with an IP address.
- Activity: show recent audited command and WOL runs from the bridge.

## Quick Start

```sh
docker compose up --build -d
```

The local compose stack starts the bridge, relay, and a fake Uptime Kuma endpoint for fresh sample status data.

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
