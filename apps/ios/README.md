# PopRocket iOS

This directory contains the iOS-first app project:

- `PopRocketKit` shared models, pairing parser, Keychain, App Group cache, bridge client, and action signing.
- `PopRocketApp` SwiftUI dashboard, pairing flow, QR scanner, and notification delegate.
- `PopRocketWatchApp` watchOS dashboard backed by WatchConnectivity snapshots from the iPhone app.
- `PopRocketWidget` WidgetKit status, health, trusted action, and Lock Screen widgets backed by App Group cache.
- `PopRocketIntents` App Intent for widget and Shortcuts actions.
- `PopRocketNotificationService` notification service extension entry point.
- `PopRocket.xcodeproj` with app, watch app, widget extension, App Intents framework, notification service extension, and unit-test targets.
- `project.yml` XcodeGen spec used to regenerate the Xcode project.

The placeholder bundle IDs use `com.poprocket.*`, and the shared App Group is `group.com.poprocket.app`, matching `AppGroupCache.defaultGroupID`.

Build and test from the repo root:

```sh
swift test --package-path apps/ios
make ios-test
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
```

Release builds retain normal `-O` performance optimization while enabling ThinLTO, dead-code stripping, copied-framework stripping, and unused asset pruning. Check an archive product against the 5 MiB installed-size budget with:

```sh
make ios-size IOS_APP_PATH=build/PopRocket.xcarchive/Products/Applications/PopRocket.app
```

`make ios-test` runs the hostless `PopRocketKitTests` scheme on an iOS simulator. The `PopRocket` scheme embeds `PopRocketWatchApp`; install the matching watchOS platform runtime in Xcode for full simulator builds. Without that runtime, Swift package tests and the iOS-target cross-build in `make quality` still validate the shared code and app source.

With the Docker stack running, pair the simulator and run a signed action:

```sh
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
```

Use the app's Activity section to verify the signed audit result.

For a screenless bridge host, use bridge settings to add a manual URL like `http://<bridge-ip>:6567`. The app fetches a short-lived pairing token from the bridge and saves that bridge URL for future dashboard/action requests.

After pairing, the iPhone app asks for notification permission, registers with APNs, and posts the APNs token to the paired bridge's relay URL. The relay fans out bridge `/v1/notify` events to registered devices; Apple Watch receives those alerts through iPhone notification mirroring, and the watchOS app receives the latest dashboard snapshot from the iPhone via WatchConnectivity.

The watchOS app shows only WOL targets that were explicitly pinned as trusted widget actions in the iPhone app. Wake taps are sent to the iPhone over WatchConnectivity; the iPhone rechecks that trust state, signs the existing `wol:<target_id>` action, and sends it directly to the bridge or through the relay fallback.

The action widget only shows explicitly pinned WOL devices and saved command tiles. Pin or unpin those trusted actions from the device and command tile option menus in the app.

The widget extension requests a five-minute timeline cadence for near-live dashboard snapshots, while still treating the App Group cache timestamp as the source of truth for freshness.

After changing target structure, regenerate the project:

```sh
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```
