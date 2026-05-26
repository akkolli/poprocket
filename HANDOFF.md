# PopRocket Handoff

Date: 2026-05-25

## Project State

This repo is a fresh PopRocket monorepo scaffold for an iOS-first homelab operations app with Go backend services.

Implemented:

- `services/bridge`: Go homelab bridge service.
  - YAML config loading and validation.
  - SQLite event/audit storage with idempotency.
  - Pairing start/complete endpoints.
  - Card endpoint with bridge host, generic REST/Uptime Kuma JSON reads, and Docker Compose status reads.
  - Notification ingest endpoint.
  - WOL packet generation and wake endpoint.
  - Signed action validation with Ed25519.
  - Allowlisted action execution for audit, WOL, and Docker container operations.
  - Outbound relay WebSocket client for fallback action delivery.
  - Relay WebSocket heartbeat to keep the bridge connection alive.

- `services/relay`: Go hosted relay service.
  - Device registration.
  - Opaque push fanout contract.
  - APNs client abstraction with log/memory implementations.
  - Bridge WebSocket routing.
  - Relay action forwarding with TTL rejection.

- `apps/ios`: buildable Xcode iOS app project plus Swift package scaffold.
  - `PopRocket.xcodeproj` generated from `project.yml`.
  - iOS app target with shared App Group entitlement and camera usage description.
  - WidgetKit extension target.
  - App Intents framework/module for widget and Shortcuts actions.
  - Notification Service Extension target.
  - `PopRocketKit` shared models, QR pairing parser, Keychain helper, App Group cache, BridgeClient, action signer, notification action router.
  - `PopRocketApp` SwiftUI dashboard, pairing view, QR scanner, notification delegate.
  - `PopRocketWidget` WidgetKit widget reading App Group cache and showing stale/fresh state.
  - `PopRocketIntents` App Intent for widget/Shortcuts actions.
  - `PopRocketNotificationService` notification service extension scaffold.

- Docs/config:
  - `README.md`, `docs/api.md`, `docs/setup.md`, `docs/threat-model.md`, `docs/templates.md`, `docs/ios.md`.
  - `configs/bridge.example.yaml`.
  - Initial templates for WOL, Docker Compose, Uptime Kuma, and generic REST.
  - `compose.yaml` dev stack with bridge and relay.

## Verification Already Done

Latest macOS verification completed on 2026-05-25 with Xcode 26.2, Swift 6.2.3, Go 1.25, Docker, and XcodeGen.

Passed:

```sh
make test
swift test --package-path apps/ios
xcodegen generate --spec apps/ios/project.yml --project apps/ios
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
xcodebuild test -quiet -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'platform=iOS Simulator,name=iPhone 17'
make docker-build
docker compose up --build -d
curl -fsS http://localhost:8080/v1/health | jq .
curl -fsS http://localhost:8080/v1/cards | jq .
./scripts/smoke_notify.sh http://localhost:8080
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
curl -fsS 'http://localhost:8080/v1/audit?limit=5' | jq .
docker compose logs --since=90s bridge relay
docker compose config
./scripts/verify_structure.sh
```

Tests passed for:

- bridge config parsing
- WOL magic packet generation
- action signature verification, Swift-generated Ed25519-compatible vector verification, and scope denial
- SQLite idempotency/audit writes
- JSONPath selection
- relay APNs opaque payload construction
- relay device lookup and bridge message routing
- relay action TTL rejection
- iOS pairing parser
- iOS action signer canonical-message and signature validity
- iOS simulator pairing against Docker bridge
- iOS simulator signed `ack` action reaching bridge audit
- relay WebSocket heartbeat staying connected beyond the old one-minute timeout window

Earlier backend smoke testing with `go run`:

- started relay on `:18081`
- started bridge on `:18080`
- hit `/v1/health`
- hit `/v1/pairing/start`
- posted `/v1/notify`

## First Checks On Mac

Run these from repo root:

```sh
go version
swift --version
docker --version
make test
swift test --package-path apps/ios
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
xcodebuild test -quiet -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'platform=iOS Simulator,name=iPhone 17'
docker compose config
docker compose up --build -d
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
```

Expected backend command:

```sh
make test
```

Regenerate the Xcode project after changing target structure:

```sh
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```

## Important Files

- Root overview: `README.md`
- Handoff: `HANDOFF.md`
- Bridge entrypoint: `services/bridge/cmd/bridge/main.go`
- Bridge HTTP routes/actions: `services/bridge/internal/server/server.go`
- Bridge config schema: `services/bridge/internal/config/config.go`
- Bridge adapters: `services/bridge/internal/adapters`
- Bridge security: `services/bridge/internal/security/verifier.go`
- Bridge storage: `services/bridge/internal/storage/sqlite.go`
- Relay routes: `services/relay/internal/server/server.go`
- Relay APNs payloads: `services/relay/internal/apns/payload.go`
- iOS shared contracts: `apps/ios/Sources/PopRocketKit/Models.swift`
- iOS Xcode project generator spec: `apps/ios/project.yml`
- iOS Xcode project: `apps/ios/PopRocket.xcodeproj`
- iOS bridge client: `apps/ios/Sources/PopRocketKit/BridgeClient.swift`
- iOS dashboard: `apps/ios/Sources/PopRocketApp`
- iOS widget: `apps/ios/Sources/PopRocketWidget/PopRocketWidget.swift`
- iOS simulator pairing helper: `scripts/ios_sim_pair.sh`
- iOS simulator action helper: `scripts/ios_sim_action.sh`

## Known Gaps

- No real APNs provider implementation yet. Relay currently has log/memory clients.
- No real encrypted envelope implementation yet. Bridge creates opaque hashes for routing tests; production needs device/bridge public-key envelope encryption.
- iOS bundle identifiers and App Group ID are placeholders (`com.poprocket.*`, `group.com.poprocket.app`); update to final Team ID/bundle/App Group values before physical-device signing.
- Physical iPhone install, APNs capability provisioning, and push delivery are not verified.
- `compose.yaml` runs the bridge as root for local SQLite volume writability with the distroless image. Production should use a writable volume owned by the service user or an init step.
- Pairing stores devices only in memory through the bridge verifier. Persist paired devices in SQLite before production use.
- Relay storage is in-memory. Persist device registrations and bridge delivery state before deploying.
- Docker adapter uses Docker Engine API but has only lightweight coverage. Add fake Docker API integration tests.
- Generic REST supports simple dot/index JSONPath only, not full JSONPath semantics.
- No arbitrary shell execution by design.

## Recommended Next Steps

1. Configure final Apple identifiers/capabilities:
   - bundle IDs
   - App Group
   - Push Notifications/APNs
   - signing team

2. Run an end-to-end physical iPhone test:
   - bridge starts
   - app scans QR
   - app fetches cards
   - script posts `/v1/notify`
   - phone receives push
   - notification action reaches bridge directly or through relay
   - WOL action writes audit result
   - widget displays freshness/staleness correctly

3. Implement real relay payload encryption:
   - Pairing should register device public keys.
   - Bridge should encrypt event envelopes for devices.
   - Relay should only see routing IDs, device tokens, APNs metadata, and ciphertext.

4. Persist production state:
   - bridge paired devices
   - relay device registrations
   - relay queued action delivery attempts

5. Add integration stack:
   - fake APNs
   - fake Docker API
   - fake Uptime Kuma status page
   - UDP WOL listener

## Useful Local Commands

Start dev stack:

```sh
docker compose up --build -d
```

Create pairing payload:

```sh
curl -X POST http://localhost:8080/v1/pairing/start
```

Send smoke notification:

```sh
./scripts/smoke_notify.sh http://localhost:8080
```

Check bridge audit:

```sh
curl http://localhost:8080/v1/audit | jq
```

Run backend tests:

```sh
make test
```

Run iOS package tests:

```sh
swift test --package-path apps/ios
```

Build the iOS app for Simulator:

```sh
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
```

Pair and run a signed simulator action:

```sh
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
curl -fsS 'http://localhost:8080/v1/audit?limit=5' | jq .
```
