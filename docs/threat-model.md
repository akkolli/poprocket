# Threat Model

## Assets

- Homelab API tokens and credentials
- Device signing keys
- Bridge relay token
- Notification event details
- Audit log integrity
- WOL, Docker, and command action scopes

## Trust Boundaries

- iOS app stores device credentials in Keychain.
- Bridge stores homelab credentials and audit history.
- Relay routes encrypted payloads and APNs metadata only.
- Widgets read from an App Group cache and must not contain long-lived secrets.

## Controls

- One-time pairing tokens with short TTLs.
- Device public keys registered during pairing.
- Signed action envelopes.
- Sensitive bridge reads require signed request headers and read scopes such as `cards:read`, `audit:read`, `monitor:read`, or `wol:read`.
- Signed reads and action envelopes expire after a five-minute clock-skew window.
- Per-action scopes such as `wol:wake:<target-id>`.
- Monitor and WOL target mutations require signed management envelopes with `monitor:write` or `wol:manage`.
- Command execution requires the `command:run` scope and explicit bridge config.
- Idempotency keys for events and action runs.
- Confirmation flags for destructive or surprising actions.
- SQLite audit records for accepted, denied, failed, and completed actions.
- Ad-hoc shell execution is disabled by default and should be constrained with `command_runner.allowed_prefixes` when enabled.

## Relay Privacy

The relay receives routing IDs, device tokens, APNs delivery metadata, `event_id`, `bridge_id`, and opaque encrypted envelopes. The display fallback can be generic. A Notification Service Extension can decrypt richer content on device when APNs wakes the app extension.

Relay logs must avoid payload bodies and homelab URLs.
