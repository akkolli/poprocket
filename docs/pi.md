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

The script writes `deploy/pi/local/bridge.yaml`, which is intentionally ignored by Git, and starts the bridge with host networking so UDP WOL packets leave from the Pi.

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

## Update

After pushing changes to GitHub, update the Pi:

```sh
cd poprocket
git pull
./scripts/pi_install.sh 192.168.0.25
```
