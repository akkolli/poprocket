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
- Relay routes scoped event references and APNs delivery metadata; it never receives homelab credentials or action request bodies.
- Widgets read from an App Group cache and must not contain long-lived secrets.

## Controls

- One-time pairing tokens with short TTLs.
- Starting a pairing session requires the installer-generated pairing access token on new bridges.
- Pairing scopes are intersected with the bridge-configured policy; a client cannot grant itself additional scopes.
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
- Relay push/WebSocket operations require the bridge relay secret. Pairing derives a bridge-scoped device token for registration and fallback actions; only that scoped token is stored in the iOS Keychain.
- Notification ingestion requires `security.notification_token` when configured.

## Relay Privacy

The relay receives routing IDs, device tokens, APNs delivery metadata, `event_id`, `bridge_id`, a short APNs display title/body, and an opaque event reference. Keep display title/body free of secrets. The current opaque reference is not an encrypted notification envelope; end-to-end encryption of richer notification content requires a future device/bridge key-agreement protocol.

Relay logs must avoid payload bodies and homelab URLs.

## Local Transport

The iOS app permits plain HTTP only for literal private, link-local, loopback, carrier-grade NAT, `.local`, or unqualified LAN hosts. Public host names require HTTPS, embedded URL credentials are rejected, and redirect destinations are checked with the same policy. `NSAllowsLocalNetworking` supports local host names without globally disabling App Transport Security.
