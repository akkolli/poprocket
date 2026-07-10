IOS_PROJECT ?= apps/ios/PopRocket.xcodeproj
IOS_SCHEME ?= PopRocket
IOS_TEST_SCHEME ?= PopRocketKitTests
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=26.2
IOS_CONFIGURATION ?= Release
IOS_ARCHIVE_PATH ?= build/PopRocket.xcarchive
IOS_EXPORT_PATH ?= build/ios-export
IOS_EXPORT_OPTIONS_PLIST ?= apps/ios/Supporting/ExportOptions.plist
IOS_APP_PATH ?= $(IOS_ARCHIVE_PATH)/Products/Applications/PopRocket.app
IOS_SIZE_BUDGET_MIB ?= 5
GOVULNCHECK_VERSION ?= v1.6.0

.PHONY: test bridge-test relay-test race vet security swift-test swift-ios-build ios-build ios-test ios-release-build ios-archive ios-export ios-package ios-size fmt docker-build verify quality

test: bridge-test relay-test

bridge-test:
	cd services/bridge && go test ./...

relay-test:
	cd services/relay && go test ./...

race:
	cd services/bridge && go test -race ./...
	cd services/relay && go test -race ./...

vet:
	cd services/bridge && go vet ./...
	cd services/relay && go vet ./...

security:
	cd services/bridge && go run golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION) ./...
	cd services/relay && go run golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION) ./...

swift-test:
	swift test --package-path apps/ios

swift-ios-build:
	swift build --package-path apps/ios --triple arm64-apple-ios17.0 --sdk "$$(xcrun --sdk iphoneos --show-sdk-path)"

ios-build:
	xcodebuild -quiet -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration Debug -destination '$(IOS_DESTINATION)' build

ios-test:
	xcodebuild test -quiet -project $(IOS_PROJECT) -scheme $(IOS_TEST_SCHEME) -destination '$(IOS_DESTINATION)'

ios-release-build:
	xcodebuild -quiet -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration $(IOS_CONFIGURATION) -destination 'generic/platform=iOS' build

ios-archive:
	mkdir -p build
	xcodebuild -quiet -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) -configuration $(IOS_CONFIGURATION) -destination 'generic/platform=iOS' -archivePath $(IOS_ARCHIVE_PATH) archive

ios-export: ios-archive
	mkdir -p $(IOS_EXPORT_PATH)
	xcodebuild -quiet -exportArchive -archivePath $(IOS_ARCHIVE_PATH) -exportPath $(IOS_EXPORT_PATH) -exportOptionsPlist $(IOS_EXPORT_OPTIONS_PLIST)

ios-package: ios-export

ios-size:
	bash ./scripts/check_ios_size.sh "$(IOS_APP_PATH)" "$(IOS_SIZE_BUDGET_MIB)"

fmt:
	cd services/bridge && gofmt -w $$(find . -name '*.go')
	cd services/relay && gofmt -w $$(find . -name '*.go')

docker-build:
	docker build -t poprocket/bridge:dev services/bridge
	docker build -t poprocket/relay:dev services/relay

verify: test vet swift-test swift-ios-build
	bash -n scripts/bridge_install.sh scripts/ios_sim_pair.sh scripts/check_ios_size.sh
	sh -n scripts/smoke_notify.sh
	docker compose config >/dev/null
	docker compose -f deploy/bridge/compose.yaml config >/dev/null
	./scripts/verify_structure.sh

quality: verify race
