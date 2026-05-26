# iOS Architecture

The app is split into:

- SwiftUI app target for pairing, dashboard refresh, and audit views.
- WidgetKit extension for status and action widgets.
- App Intents for widget button taps and Shortcuts.
- Notification handling for actionable notifications.
- App Group cache for card snapshots.
- Keychain storage for pairing credentials and signing keys.

Widgets render cached data and a freshness label. They do not pretend to be live dashboards. App Intents and notification actions try the direct bridge URL first, then fall back to relay delivery.

The Xcode project lives at `apps/ios/PopRocket.xcodeproj` and is generated from `apps/ios/project.yml` with XcodeGen. Current placeholder identifiers are `com.poprocket.*` and `group.com.poprocket.app`; replace them with final Apple Developer identifiers before physical-device signing.

For local simulator testing, run the Docker stack and then use `scripts/ios_sim_pair.sh` to pair the app with the bridge. `scripts/ios_sim_action.sh` launches the paired app with an action request and is useful for verifying signed action delivery into the bridge audit log.
