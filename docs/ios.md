# iOS Architecture

## Release Size

PopRocket keeps the iPhone app, widget, notification service, App Intents framework, shared security/networking framework, and watch app in the product. Release builds use performance-oriented `-O`, whole-module compilation, ThinLTO, dead-code stripping, symbol stripping, and unused asset pruning. They do not use `-Osize`, remove features, or lower asset quality.

The installed bundle budget is 5 MiB. Measure an archived app with `make ios-size IOS_APP_PATH=/path/to/PopRocket.app`; the command also reports a ZIP-compressed reference size and fails when the installed budget is exceeded.

The app is split into:

- SwiftUI app target for pairing, dashboard refresh, and audit views.
- watchOS app target for compact bridge status on Apple Watch.
- WidgetKit extension for status and action widgets.
- App Intents for widget button taps and Shortcuts.
- Notification handling for actionable notifications.
- WatchConnectivity sync from the iPhone dashboard to the watch app.
- App Group cache for status snapshots.
- Keychain storage for pairing credentials and signing keys.

Widgets render cached data and a freshness label. They do not pretend to be live dashboards. App Intents and notification actions try the direct bridge URL first, then fall back to relay delivery.

The iPhone app owns APNs registration after pairing. Pairing explains notification access before the system prompt; the app never prompts on first launch. The Notifications settings pane shows permission/relay readiness, opens iOS Settings when blocked, and can refresh registration. Apple Watch notification delivery uses iPhone notification mirroring, while the watchOS app receives dashboard snapshots through WatchConnectivity.

Apple Watch wake actions are limited to WOL targets explicitly trusted as widget actions on the iPhone. The watch sends an immediate WatchConnectivity message; the iPhone verifies the trusted target, signs `wol:<target_id>`, and sends it directly to the bridge or through the relay action fallback.

Bridge Settings owns the multi-bridge lifecycle: add by QR or manual URL, set a local display name during pairing, switch active bridge, rename local display names, reconnect an existing bridge URL to refresh scopes after bridge changes, and remove stale bridges with confirmation and inline progress.

The bridge list treats active selection and live connectivity as separate states. A bridge can be selected without being online; only a fresh health check should show the active bridge as online. Switching bridges shows inline verification progress and reports connection failures in Bridge Settings. Reconnect verifies that the URL still belongs to the selected bridge ID; if it belongs to a different bridge, the app reports that mismatch and the user should add it as a new bridge instead.

The Xcode project lives at `apps/ios/PopRocket.xcodeproj` and is generated from `apps/ios/project.yml` with XcodeGen. Current placeholder identifiers are `com.poprocket.*` and `group.com.poprocket.app`; replace them with final Apple Developer identifiers before physical-device signing.

Simulator builds that include `PopRocketWatchApp` require the matching watchOS simulator runtime installed in Xcode, not just the watchOS SDK.

For local simulator testing, run the Docker stack and then use `scripts/ios_sim_pair.sh` to pair the app with the bridge. `scripts/ios_sim_action.sh` launches the paired app with an action request and is useful for verifying signed action delivery into the bridge audit log.
