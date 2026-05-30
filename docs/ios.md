# iOS Architecture

The app is split into:

- SwiftUI app target for pairing, dashboard refresh, and audit views.
- WidgetKit extension for status and action widgets.
- App Intents for widget button taps and Shortcuts.
- Notification handling for actionable notifications.
- App Group cache for status snapshots.
- Keychain storage for pairing credentials and signing keys.

Widgets render cached data and a freshness label. They do not pretend to be live dashboards. App Intents and notification actions try the direct bridge URL first, then fall back to relay delivery.

Bridge Settings owns the multi-bridge lifecycle: add by QR or manual URL, set a local display name during pairing, switch active bridge, rename local display names, reconnect an existing bridge URL to refresh scopes after bridge changes, and remove stale bridges with confirmation and inline progress.

The bridge list treats active selection and live connectivity as separate states. A bridge can be selected without being online; only a fresh health check should show the active bridge as online. Switching bridges shows inline verification progress and reports connection failures in Bridge Settings. Reconnect verifies that the URL still belongs to the selected bridge ID; if it belongs to a different bridge, the app reports that mismatch and the user should add it as a new bridge instead.

The Xcode project lives at `apps/ios/PopRocket.xcodeproj` and is generated from `apps/ios/project.yml` with XcodeGen. Current placeholder identifiers are `com.poprocket.*` and `group.com.poprocket.app`; replace them with final Apple Developer identifiers before physical-device signing.

For local simulator testing, run the Docker stack and then use `scripts/ios_sim_pair.sh` to pair the app with the bridge. `scripts/ios_sim_action.sh` launches the paired app with an action request and is useful for verifying signed action delivery into the bridge audit log.
