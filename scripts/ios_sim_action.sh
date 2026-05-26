#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-iPhone 17}"
ACTION_ID="${2:-ack}"
EVENT_ID="${POPROCKET_RUN_EVENT_ID:-}"
CONFIRMED="${POPROCKET_RUN_CONFIRMED:-}"
APP_ID="${POPROCKET_IOS_BUNDLE_ID:-com.poprocket.app}"
APP_PATH="${POPROCKET_IOS_APP_PATH:-}"

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/PopRocket.app' -type d -print -quit)"
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "PopRocket.app was not found. Build the simulator app first:" >&2
  echo "  xcodebuild -project apps/ios/PopRocket.xcodeproj -scheme PopRocket -destination 'generic/platform=iOS Simulator' build" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl install "$DEVICE" "$APP_PATH"

env_args=(SIMCTL_CHILD_POPROCKET_RUN_ACTION_ID="$ACTION_ID")
if [[ -n "$EVENT_ID" ]]; then
  env_args+=(SIMCTL_CHILD_POPROCKET_RUN_EVENT_ID="$EVENT_ID")
fi
if [[ -n "$CONFIRMED" ]]; then
  env_args+=(SIMCTL_CHILD_POPROCKET_RUN_CONFIRMED="$CONFIRMED")
fi

env "${env_args[@]}" xcrun simctl launch --terminate-running-process "$DEVICE" "$APP_ID" >/dev/null
echo "Launched PopRocket to run action '$ACTION_ID' on $DEVICE."
