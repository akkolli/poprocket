# Raspberry Pi Bridge

Run the bridge on the Pi when the Pi is the machine that can reach your LAN broadcast domain for Wake-on-LAN.

## Install

On the Pi:

```sh
sudo apt update
sudo apt install -y git docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Log out and back in after adding the Docker group, then clone the repo:

```sh
git clone git@github.com:akkolli/poprocket.git
cd poprocket
./scripts/pi_install.sh 192.168.0.25
```

Use your Pi's real LAN IP or hostname instead of `192.168.0.25`.

The script creates `deploy/pi/local/bridge.yaml` if it does not already exist. That file is intentionally ignored by Git, and the bridge starts with host networking so UDP WOL packets leave from the Pi.

## Pair iPhone

In PopRocket:

1. Tap **Pair Bridge**.
2. Enter `http://<pi-ip>:6567` in the manual bridge field.
3. Tap **Connect**.

No QR code or Pi display is required. The app asks the Pi bridge for a short-lived pairing token and saves the typed Pi URL as the first direct URL.

## Wake Devices

In PopRocket:

1. Open **Wake-on-LAN**.
2. Tap **Add Device**.
3. Enter the device name, Ethernet MAC address, LAN IP, and UDP port `9`.
4. Save.
5. Put the target machine to sleep and tap its power button.

The bridge sends the magic packet directly from the Pi. The external `wakeonlan` shell command is not required.

## Run Commands

PopRocket can also run signed shell commands through the bridge. Enable it in `deploy/pi/local/bridge.yaml`:

```yaml
command_runner:
  enabled: true
  allow_ad_hoc: true
  shell: "/bin/sh"
  timeout_seconds: 30
  max_output_bytes: 4096
  allowed_prefixes:
    - "ssh -o BatchMode=yes -o ConnectTimeout=5 lepton@pluto "
```

With that prefix, the iOS command field can run:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=5 lepton@pluto wake neptune
```

Leaving `allowed_prefixes` empty allows any command that the bridge container can execute.

The bridge container includes an SSH client, but it needs credentials inside the container. If your host user already has SSH working, mount that `.ssh` directory into the bridge service:

```yaml
volumes:
  - ./local/bridge.yaml:/etc/poprocket/bridge.yaml:ro
  - bridge-data:/var/lib/poprocket
  - /home/lepton/.ssh:/root/.ssh:ro
```

For key-only SSH, make sure `/home/lepton/.ssh` contains the private key and `known_hosts` entry for `pluto`. The `BatchMode=yes` option prevents password/passphrase prompts from hanging the bridge action; if the key needs an interactive passphrase, use a dedicated key for PopRocket or mount an SSH agent socket instead.

Rebuild after changing the Docker image or compose file. Re-pair the app after enabling command execution so the phone gets the `command:run` scope.

## Update

After pushing changes to GitHub, update the Pi:

```sh
cd poprocket
git pull
./scripts/pi_install.sh 192.168.0.25
```
