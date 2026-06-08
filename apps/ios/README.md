# PopRocket iOS

This directory contains the iOS-first app project:

- `PopRocketKit` shared models, pairing parser, Keychain, App Group cache, bridge client, and action signing.
- `PopRocketApp` SwiftUI dashboard, pairing flow, QR scanner, and notification delegate.
- `PopRocketWidget` WidgetKit status, health, trusted action, and Lock Screen widgets backed by App Group cache.
- `PopRocketIntents` App Intent for widget and Shortcuts actions.
- `PopRocketNotificationService` notification service extension entry point.
- `PopRocket.xcodeproj` with app, widget extension, App Intents framework, notification service extension, and unit-test targets.
- `project.yml` XcodeGen spec used to regenerate the Xcode project.

The placeholder bundle IDs use `com.poprocket.*`, and the shared App Group is `group.com.poprocket.app`, matching `AppGroupCache.defaultGroupID`.

Build and test from the repo root:

```sh
swift test --package-path apps/ios
xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build
xcodebuild test -quiet -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'platform=iOS Simulator,name=iPhone 17'
```

With the Docker stack running, pair the simulator and run a signed action:

```sh
./scripts/ios_sim_pair.sh 'iPhone 17'
./scripts/ios_sim_action.sh 'iPhone 17' ack
curl -fsS 'http://localhost:6567/v1/audit?limit=5' | jq .
```

For a screenless bridge host, use bridge settings to add a manual URL like `http://<bridge-ip>:6567`. The app fetches a short-lived pairing token from the bridge and saves that bridge URL for future dashboard/action requests.

The action widget only shows explicitly pinned WOL devices and saved command tiles. Pin or unpin those trusted actions from the device and command tile option menus in the app.

After changing target structure, regenerate the project:

```sh
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```
