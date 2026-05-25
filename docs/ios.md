# iOS Architecture

The app is split into:

- SwiftUI app target for pairing, dashboard refresh, and audit views.
- WidgetKit extension for status and action widgets.
- App Intents for widget button taps and Shortcuts.
- Notification handling for actionable notifications.
- App Group cache for card snapshots.
- Keychain storage for pairing credentials and signing keys.

Widgets render cached data and a freshness label. They do not pretend to be live dashboards. App Intents and notification actions try the direct bridge URL first, then fall back to relay delivery.
