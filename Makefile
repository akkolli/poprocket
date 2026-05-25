.PHONY: test bridge-test relay-test fmt docker-build verify

test: bridge-test relay-test

bridge-test:
	cd services/bridge && go test ./...

relay-test:
	cd services/relay && go test ./...

fmt:
	cd services/bridge && gofmt -w $$(find . -name '*.go')
	cd services/relay && gofmt -w $$(find . -name '*.go')

docker-build:
	docker build -t poprocket/bridge:dev services/bridge
	docker build -t poprocket/relay:dev services/relay

verify:
	./scripts/verify_structure.sh
