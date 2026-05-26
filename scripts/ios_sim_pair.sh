#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-iPhone 17}"
BRIDGE_URL="${POPROCKET_BRIDGE_URL:-http://localhost:8080}"
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

pairing_payload="$(
  curl -fsS -X POST "$BRIDGE_URL/v1/pairing/start" |
    ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("qr_payload")'
)"

SIMCTL_CHILD_POPROCKET_PAIRING_PAYLOAD="$pairing_payload" \
  xcrun simctl launch --terminate-running-process "$DEVICE" "$APP_ID" >/dev/null

echo "Launched PopRocket with a fresh pairing payload on $DEVICE."
