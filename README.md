# PopRocket

PopRocket is a native iPhone control surface for a private homelab. It pairs a polished SwiftUI app with a trusted bridge running inside your LAN so the phone can monitor devices and services, wake machines, run SSH or shell commands, save common commands as reusable action tiles, and manage multiple bridges without exposing internal systems directly to the internet.

The bridge is the local authority. It owns SSH keys and LAN access, sends Wake-on-LAN packets, performs TCP/HTTP health checks, stores monitor state and action audit history in SQLite, and exposes a narrow API to paired devices. The iPhone never needs broad network access or SSH credentials; it asks the bridge to perform scoped operations and displays the result.

This repository is organized as a monorepo:

- `apps/ios` - SwiftUI iPhone and Apple Watch app source, WidgetKit widget, App Intents, notification handling, Keychain, WatchConnectivity sync, and App Group cache helpers.
- `services/bridge` - Go bridge service that runs inside the homelab, owns secrets, sends WOL packets, runs explicitly enabled shell commands, checks monitor health, exposes status snapshots/actions, stores SQLite state and audit history, and connects outbound to the relay.
- `services/relay` - Go relay service for token-authenticated APNs fanout and bridge/device action delivery. Relay event references are intentionally opaque; short notification title/body text remains visible to APNs and the relay.
- `docs` - setup guide, API contract, Fireman notification contract, design system, threat model, and template examples.
- `configs` - starter bridge config and reusable templates.

## Naming Model

PopRocket is the product and iPhone app. A bridge is any trusted LAN host running the PopRocket bridge service; it can be a mini PC, NAS, Docker host, server, VM, or compact always-on computer. The default user-visible bridge name is `Local Bridge`, custom bridge names should describe the host or location, and generated bridge IDs use `bridge-<host>` so multiple bridges can coexist. Hardware-specific bridge names are legacy migration inputs only and should not appear in the product UI, current install path, Docker resources, or setup docs.

## Current App Surface

- Bridge status/settings: see bridge reachability and uptime, pair by QR or URL, name bridges, switch active bridge, reconnect an existing bridge to refresh scopes, and remove old bridges.
- Health: add TCP/HTTP monitors through signed bridge management requests, see up/down state, response time, last check time, current up/down duration, and timestamped last-known health after app relaunches or bridge outages.
- Commands: run ad-hoc bridge commands, save frequent commands as named bridge-scoped action tiles, see each tile's last run status, edit/delete tiles, and see command output.
- Wake-on-LAN: add devices through signed bridge management requests, derive broadcast addresses from device IPs, wake devices with visible sent/failed feedback, and auto-create SSH health checks for WOL targets with an IP address.
- Activity: show recent audited command and WOL runs from the bridge.
- Notifications and Watch: register the iPhone APNs token with the relay after pairing, mirror important bridge notifications to iPhone/Apple Watch, sync a compact bridge dashboard to the Apple Watch app, and wake trusted WOL targets from the watch through the iPhone.

## Quick Start

```sh
docker compose up --build -d
```

The local compose stack starts the bridge, relay, and a fake Uptime Kuma endpoint for fresh sample status data.

For a local bridge host that can send Wake-on-LAN packets from your LAN, see [`docs/bridge.md`](docs/bridge.md):

```sh
./scripts/bridge_install.sh 192.168.0.25 "Home Bridge"
```

Create a pairing QR from the bridge:

```sh
curl -X POST http://localhost:6567/v1/pairing/start \
  -H 'Authorization: Bearer dev-pairing-token'
```

For a screenless bridge host, use the iOS app's manual pairing field with `http://<bridge-ip>:6567` and the pairing code printed by the installer; no QR display is required.

Send an actionable notification:

```sh
curl -X POST http://localhost:6567/v1/notify \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer dev-notify-token' \
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

Fireman dependency security alerts use the same notification path; see [`docs/fireman.md`](docs/fireman.md).

## Local Verification

```sh
./scripts/verify_structure.sh
```

When Go and Docker are installed:

```sh
make test
make quality
make security
make ios-size IOS_APP_PATH=/path/to/PopRocket.app
make docker-build
docker compose config
```

`make quality` runs Go tests, vet, race detection, Swift package tests, shell syntax checks, Compose validation, and repository structure checks. `make security` runs the official Go vulnerability analyzer and requires network access to refresh its vulnerability database. `make ios-size` reports installed and compressed bundle sizes and rejects Release products above the 5 MiB installed-size budget.
The Go modules and container builders require the patched Go 1.25.12 toolchain; with Go's default `GOTOOLCHAIN=auto`, an older local tool downloads it automatically.

When Xcode is installed:

```sh
swift test --package-path apps/ios
make ios-test
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
```

After the action finishes, open the app's Activity section to inspect the signed audit feed.

`make ios-test` uses a hostless `PopRocketKitTests` scheme, so networking and security tests can run on iOS without building the watch app. The iPhone scheme embeds a watchOS app; install the matching watchOS platform runtime in Xcode before simulator builds that include it.

## Design Constraints

The relay never stores homelab API secrets or plaintext action requests. It does see the minimal APNs display title/body and an opaque event reference; full end-to-end notification-envelope encryption is not yet implemented. The bridge owns integrations, action policy, idempotency, and audit writes. iOS widgets read a shared App Group cache, request near-live five-minute timeline refreshes, and always show freshness because WidgetKit does not allow continuously running dashboards.

The iOS visual and interaction rules are captured in [`docs/design-system.md`](docs/design-system.md). New UI should use the shared `AppDesign` surfaces and feedback primitives instead of adding feature-local control styling.
