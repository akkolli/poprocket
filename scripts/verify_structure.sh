#!/usr/bin/env sh
set -eu

required="
README.md
go.work
compose.yaml
configs/bridge.example.yaml
services/bridge/go.mod
services/bridge/cmd/bridge/main.go
services/bridge/internal/server/server.go
services/bridge/internal/wol/wol_test.go
services/relay/go.mod
services/relay/cmd/relay/main.go
services/relay/internal/server/server.go
services/relay/internal/apns/payload_test.go
apps/ios/Package.swift
apps/ios/Sources/PopRocketKit/Models.swift
apps/ios/Sources/PopRocketApp/PopRocketApp.swift
apps/ios/Sources/PopRocketWidget/PopRocketWidget.swift
docs/api.md
docs/threat-model.md
"

for path in $required; do
  if [ ! -f "$path" ]; then
    echo "missing: $path" >&2
    exit 1
  fi
done

echo "PopRocket structure verified"
