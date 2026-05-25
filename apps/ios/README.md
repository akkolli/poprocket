# PopRocket iOS

This directory contains the iOS-first app source scaffold:

- `PopRocketKit` shared models, pairing parser, Keychain, App Group cache, bridge client, and action signing.
- `PopRocketApp` SwiftUI dashboard, pairing flow, QR scanner, and notification delegate.
- `PopRocketWidget` WidgetKit status widget that reads App Group cache and marks stale cards.
- `PopRocketIntents` App Intent for widget and Shortcuts actions.
- `PopRocketNotificationService` notification service extension entry point.

Create an Xcode iOS app workspace with these sources as separate app/extension targets. Set the App Group entitlement to the same value used by `AppGroupCache.defaultGroupID`.
