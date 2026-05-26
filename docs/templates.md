# Templates

PopRocket templates are intentionally typed. They avoid arbitrary shell execution and map each control to explicit scopes.

## WOL

Use `configs/templates/wol.yaml`. The bridge sends UDP broadcast packets from inside the homelab, which avoids relying on iOS local-network broadcast behavior.

## Docker / Compose

Use `configs/templates/docker-compose.yaml`. v1 supports allowlisted operations through the Docker Engine API. Each action needs an explicit scope such as `docker:restart:core-web-1`.

## Uptime Kuma

Use `configs/templates/uptime-kuma.yaml`. v1 reads public status-page data only. Treat status-page values as cached and less responsive than the Uptime Kuma dashboard.

## Generic REST / JSON

Use `configs/templates/generic-rest.yaml`. Headers can reference bridge-side secrets by name so widget configs do not contain raw API keys.

For a header mapping such as `Authorization: ups_api_token`, set `POPROCKET_SECRET_UPS_API_TOKEN` in the bridge environment.
