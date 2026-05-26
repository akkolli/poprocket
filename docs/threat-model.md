# Threat Model

## Assets

- Homelab API tokens and credentials
- Device signing keys
- Bridge relay token
- Notification event details
- Audit log integrity
- WOL and Docker action scopes

## Trust Boundaries

- iOS app stores device credentials in Keychain.
- Bridge stores homelab credentials and audit history.
- Relay routes encrypted payloads and APNs metadata only.
- Widgets read from an App Group cache and must not contain long-lived secrets.

## Controls

- One-time pairing tokens with short TTLs.
- Device public keys registered during pairing.
- Signed action envelopes.
- Per-action scopes such as `wol:wake:<target-id>`.
- Idempotency keys for events and action runs.
- Confirmation flags for destructive or surprising actions.
- SQLite audit records for accepted, denied, failed, and completed actions.
- No arbitrary shell execution in v1.

## Relay Privacy

The relay receives routing IDs, device tokens, APNs delivery metadata, `event_id`, `bridge_id`, and opaque encrypted envelopes. The display fallback can be generic. A Notification Service Extension can decrypt richer content on device when APNs wakes the app extension.

Relay logs must avoid payload bodies and homelab URLs.
