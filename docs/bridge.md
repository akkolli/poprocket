# PopRocket Bridge

Run the bridge on any always-on host inside your LAN that can reach the devices and services you want PopRocket to operate. The host can be a mini PC, NAS, server, Docker host, VM, or compact always-on computer.

## Naming

Use `PopRocket` for the app/product, `bridge` for the local authority service, `Local Bridge` as the default display name, and custom names like `Pluto`, `Rack Bridge`, or `Workshop Bridge` when a home has more than one bridge. Generated IDs use `bridge-<host>` and Docker resources use `poprocket-bridge`. Older hardware-specific bridge names, IDs, containers, and paths are migration inputs only.

## Install

On the bridge host:

```sh
sudo apt update
sudo apt install -y git docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Log out and back in after adding the Docker group, then clone the repo:

```sh
git clone git@github.com:akkolli/poprocket.git
cd poprocket
./scripts/bridge_install.sh 192.168.0.25 "Home Bridge"
```

Use the bridge host's real LAN IP or hostname instead of `192.168.0.25`, and choose a bridge name that describes the host or location. The bridge can run on a mini PC, NAS, server, Docker host, VM, compact computer, or any always-on LAN machine. New configs derive a stable bridge ID from the host, such as `bridge-pluto` or `bridge-192-168-0-25`, so multiple bridges do not collide in the app.

The script creates `deploy/bridge/local/bridge.yaml` with mode `0600` if it does not already exist. That file is intentionally ignored by Git. A short-lived init container copies it into a private volume owned by UID `10001`; the long-running bridge remains non-root and starts with host networking so UDP WOL packets leave from the bridge host. Older generated configs are migrated to the current bridge naming model.

## Pair iPhone

In PopRocket:

1. Tap **Add Bridge**.
2. Enter `http://<bridge-ip>:6567` in the manual bridge field.
3. Enter the pairing code printed by `bridge_install.sh`.
4. Tap **Verify & Save**.

No QR code or attached display is required. The app asks the bridge for a short-lived pairing token and saves the typed bridge URL as the first direct URL.

## Wake Devices

In PopRocket:

1. Open **Wake-on-LAN**.
2. Tap **Add Device**.
3. Enter the device name, Ethernet MAC address, LAN IP, and UDP port `9`.
4. Save.
5. Put the target machine to sleep and tap its power button.

The bridge sends the magic packet directly from the bridge host. The external `wakeonlan` shell command is not required.

## Run Commands

PopRocket can also run signed shell commands through the bridge. Enable it in `deploy/bridge/local/bridge.yaml`:

```yaml
command_runner:
  enabled: true
  allow_ad_hoc: true
  allow_shell_operators: false
  shell: "/bin/sh"
  timeout_seconds: 30
  max_output_bytes: 4096
  allowed_prefixes:
    - "ssh user@server"
    - "ssh -o BatchMode=yes -o ConnectTimeout=5 user@server"
```

With those prefixes, the iOS command field can run either form:

```sh
ssh user@server wake-desktop
ssh user@server wake desktop
ssh -o BatchMode=yes -o ConnectTimeout=5 user@server wake desktop
```

Ad-hoc execution requires at least one `allowed_prefixes` entry; an empty allowlist is rejected at startup. Prefixes are matched at command-token boundaries. Shell control operators such as `;`, `|`, redirections, backticks, and `$()` are rejected unless `allow_shell_operators` is explicitly enabled. Add `command:run` to `security.default_scopes`, then reconnect the bridge in the app, only after this policy is configured.

The bridge container includes an SSH client, but command execution and SSH credential mounts are disabled by default. Use a dedicated, narrowly scoped key instead of mounting the host user's entire `.ssh` directory. For example, mount only that key into the unprivileged service account:

```yaml
volumes:
  - ./local/bridge.yaml:/etc/poprocket/bridge.yaml:ro
  - poprocket-bridge-data:/var/lib/poprocket
  - ./local/poprocket_ed25519:/home/poprocket/.ssh/id_ed25519:ro
```

The bridge runs as UID `10001`, not root. Ensure the dedicated key is readable by that UID without making it world-readable. SSH runs noninteractively and uses `StrictHostKeyChecking=accept-new`; review the resulting known-host entry after the first trusted connection.

The bridge forces SSH commands into noninteractive mode with a short connect timeout so password and passphrase prompts fail fast instead of hanging the app. If the key needs an interactive passphrase, mount a constrained SSH agent socket instead of removing key protection.

Test the exact path the app uses from the bridge host:

```sh
docker compose -f deploy/bridge/compose.yaml exec bridge \
  ssh -o BatchMode=yes -o ConnectTimeout=5 user@server wake-desktop
```

If that fails with `Permission denied (publickey)`, the bridge container cannot use the mounted key. If it succeeds there, the app command should succeed too after re-pairing.

`scripts/bridge_install.sh` leaves command execution disabled. On upgrades, it also disables legacy ad-hoc execution when no allowlist was configured.

Rebuild after changing the Docker image or compose file. After changing bridge scopes, open Bridge Settings in the app and tap the reconnect button for that bridge so the phone refreshes `cards:read`, `audit:read`, `monitor:read`, `monitor:write`, `wol:read`, `wol:manage`, `wol:wake:*`, and `command:run` as needed.

## Update

After pushing changes to GitHub, update the bridge host:

```sh
cd poprocket
git pull
./scripts/bridge_install.sh 192.168.0.25 "Home Bridge"
```
