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

- `services/relay`: Go hosted relay service.
  - Device registration.
  - Opaque push fanout contract.
  - APNs client abstraction with log/memory implementations.
  - Bridge WebSocket routing.
  - Relay action forwarding with TTL rejection.

- `apps/ios`: Swift source scaffold.
  - `PopRocketKit` shared models, QR pairing parser, Keychain helper, App Group cache, BridgeClient, action signer, notification action router.
  - `PopRocketApp` SwiftUI dashboard, pairing view, QR scanner, notification delegate.
  - `PopRocketWidget` WidgetKit widget reading App Group cache and showing stale/fresh state.
  - `PopRocketIntents` App Intent for widget/Shortcuts actions.
  - `PopRocketNotificationService` notification service extension scaffold.

- Docs/config:
  - `README.md`, `docs/api.md`, `docs/setup.md`, `docs/threat-model.md`, `docs/templates.md`, `docs/ios.md`.
  - `configs/bridge.example.yaml`.
  - Initial templates for WOL, Docker Compose, Uptime Kuma, and generic REST.
  - `compose.yaml` dev stack.

## Verification Already Done

This Linux environment did not have Go, Swift, or Docker preinstalled. I downloaded a temporary Go toolchain into `/tmp/go` and verified the backend.

Passed:

```sh
PATH=/tmp/go/bin:$PATH make test
./scripts/verify_structure.sh
```

Backend tests passed for:

- bridge config parsing
- WOL magic packet generation
- action signature verification and scope denial
- SQLite idempotency/audit writes
- JSONPath selection
- relay APNs opaque payload construction
- relay device lookup and bridge message routing
- relay action TTL rejection

Smoke tested with `go run`:

- started relay on `:18081`
- started bridge on `:18080`
- hit `/v1/health`
- hit `/v1/pairing/start`
- posted `/v1/notify`

Not verified here because toolchain was unavailable:

```sh
swift test --package-path apps/ios
docker compose config
docker compose up --build
```

## First Checks On Mac

Run these from repo root:

```sh
go version
swift --version
docker --version
make test
swift test --package-path apps/ios
docker compose config
docker compose up --build
```

Expected backend command:

```sh
make test
```

Expected iOS command may reveal Apple-target packaging issues because `apps/ios` is currently a Swift package scaffold, not a full Xcode project with app and extension targets.

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
- iOS bridge client: `apps/ios/Sources/PopRocketKit/BridgeClient.swift`
- iOS dashboard: `apps/ios/Sources/PopRocketApp`
- iOS widget: `apps/ios/Sources/PopRocketWidget/PopRocketWidget.swift`

## Known Gaps

- No real APNs provider implementation yet. Relay currently has log/memory clients.
- No real encrypted envelope implementation yet. Bridge creates opaque hashes for routing tests; production needs device/bridge public-key envelope encryption.
- iOS source is scaffolded as Swift package targets. A macOS/Xcode agent should create proper app, widget, intent, and notification extension targets with entitlements.
- App Group ID is hardcoded as `group.com.poprocket.app`; update to the final bundle/team identifiers.
- Action signing compatibility needs Xcode verification. Swift uses CryptoKit `Curve25519.Signing`, while Go verifier expects Ed25519 public keys/signatures. This must be reconciled before real signed actions work.
- Pairing stores devices only in memory through the bridge verifier. Persist paired devices in SQLite before production use.
- Relay storage is in-memory. Persist device registrations and bridge delivery state before deploying.
- Docker adapter uses Docker Engine API but has only lightweight coverage. Add fake Docker API integration tests.
- Generic REST supports simple dot/index JSONPath only, not full JSONPath semantics.
- No arbitrary shell execution by design.

## Recommended Next Steps

1. On macOS, create an Xcode workspace/project around `apps/ios` with:
   - iOS app target
   - WidgetKit extension
   - App Intents target/module
   - Notification Service Extension
   - shared App Group entitlement
   - camera usage description for QR scanning

2. Fix the signing mismatch:
   - Either switch Swift signing to Ed25519 via CryptoKit support or another vetted library, or switch Go verifier to the exact signature scheme used by iOS.
   - Add cross-language test vectors.

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

6. Run an end-to-end physical iPhone test:
   - bridge starts
   - app scans QR
   - app fetches cards
   - script posts `/v1/notify`
   - phone receives push
   - notification action reaches bridge directly or through relay
   - WOL action writes audit result
   - widget displays freshness/staleness correctly

## Useful Local Commands

Start dev stack:

```sh
docker compose up --build
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
