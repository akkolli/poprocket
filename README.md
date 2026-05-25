# PopRocket

PopRocket is an iOS-first homelab operations control plane. It pairs a native iOS app with a self-hosted bridge and an opaque hosted relay so homelab scripts can send actionable notifications, widgets can show cached status, and every privileged action is scoped and audited.

This repository is organized as a monorepo:

- `apps/ios` - SwiftUI app source, WidgetKit widget, App Intents, notification handling, Keychain, and App Group cache helpers.
- `services/bridge` - Go bridge service that runs inside the homelab, owns secrets, sends WOL packets, exposes cards/actions, stores SQLite audit history, and connects outbound to the relay.
- `services/relay` - Go relay service for APNs fanout and encrypted bridge/device action delivery. Relay payloads are intentionally opaque.
- `docs` - setup guide, API contract, threat model, and template examples.
- `configs` - starter bridge config and reusable templates.

## Quick Start

```sh
cp configs/bridge.example.yaml bridge.yaml
docker compose up --build
```

Then create a pairing QR from the bridge:

```sh
curl -X POST http://localhost:8080/v1/pairing/start
```

Send an actionable notification:

```sh
curl -X POST http://localhost:8080/v1/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "severity": "warning",
    "title": "Backup failed",
    "body": "nas01 nightly backup exited with status 2",
    "source": "cron/nas01",
    "actions": [
      {"id": "ack", "title": "Ack", "kind": "audit"},
      {"id": "wake_nas", "title": "Wake NAS", "kind": "wol", "scope": "wol:wake:nas01"}
    ],
    "card_ids": ["bridge_host"],
    "ttl_seconds": 900,
    "idempotency_key": "backup-nas01-2026-05-25"
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
```

## Design Constraints

The relay never stores homelab API secrets or plaintext action payloads. The bridge owns integrations, action policy, idempotency, and audit writes. iOS widgets read a shared App Group cache and always show freshness because widgets are not live dashboards.
