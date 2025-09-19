# Sprinkler Controller Deployment Guide

This guide captures the exact configuration that is now running on the Raspberry Pi controller.
It documents the wiring plan for the 16 active relays, the required `.env` configuration, and the
steps to validate the service before moving on to UI polish.

The Raspberry Pi runs the FastAPI backend from this repo and is paired with the Sprink! iOS app.
All commands below assume you are connected to the Pi via SSH as `tybuell` and that the project
lives in `/srv/sprinkler-controller`.

---

## 1. Hardware wiring reference

The relay board is already wired exactly as shown in the photo. Each channel maps to a specific BCM
GPIO pin. Only these 16 pins are allowed to toggle valves; everything else is blocked in software to
prevent accidental changes to power, ground, I²C, SPI, or UART.

| Relay position | BCM pin | Physical pin | Notes |
| -------------- | ------- | ------------ | ----- |
| 1 (leftmost)   | 12      | 32           | PWM0 capable |
| 2              | 16      | 36           | Safe GPIO |
| 3              | 20      | 38           | PCM DIN |
| 4              | 21      | 40           | PCM DOUT |
| 5              | 26      | 37           | Safe GPIO |
| 6              | 19      | 35           | PCM FS |
| 7              | 13      | 33           | PWM1 capable |
| 8              | 6       | 31           | Safe GPIO |
| 9              | 5       | 29           | Safe GPIO |
| 10             | 11      | 23           | SPI SCLK (dedicated to relay now) |
| 11             | 9       | 21           | SPI MISO (dedicated) |
| 12             | 10      | 19           | SPI MOSI (dedicated) |
| 13             | 22      | 15           | Safe GPIO |
| 14             | 27      | 13           | Safe GPIO |
| 15             | 17      | 11           | Safe GPIO |
| 16 (rightmost) | 4       | 7            | Safe GPIO |

> ✅ **Do not** wire additional loads to other GPIO pins unless you also update the allow list below.

---

## 2. Raspberry Pi preparation

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Reconnect, then install the runtime packages. Pigpio handles low-level GPIO access; FastAPI and the
other Python dependencies run inside the project virtual environment.

```bash
sudo apt install -y git python3 python3-venv python3-pip python3-rpi.gpio pigpio jq
sudo systemctl enable --now pigpiod
```

`jq` is optional but makes the JSON responses easier to read when verifying the API.

---

## 3. Project layout on the Pi

All backend code lives at `/srv/sprinkler-controller`:

```bash
sudo mkdir -p /srv/sprinkler-controller
sudo chown $USER:$USER /srv/sprinkler-controller
cd /srv/sprinkler-controller
```

Clone or copy the backend code into this directory. If you update the repo on your Mac first, use
SCP to transfer it:

```bash
scp -r ./sprinkler-backend tybuell@sprinkler:/srv/sprinkler-controller
```

Create and activate the virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
pip install -r requirements.txt
```

If no `requirements.txt` is present, manually install the known dependencies:

```bash
pip install fastapi uvicorn[standard] python-dotenv pigpio RPi.GPIO
```

---

## 4. Environment configuration (`.env`)

The `.env` file locks the backend to only control the safe 16-pin set, keeps UART/I²C reserved pins
disabled, and defines the HTTP port.

```
SPRINKLER_API_PORT=5000
SPRINKLER_GPIO_ALLOW=12,16,20,21,26,19,13,6,5,11,9,10,22,27,17,4
SPRINKLER_GPIO_DENY=2,3,14,15
```

* Keep the pins listed exactly as shown unless you rewire the relay board.
* Never overwrite `.env` when deploying updates; edit it in place if wiring changes later.

---

## 5. Manual verification

Before enabling the systemd service, sanity-check the API while the virtual environment is active.

```bash
uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
```

In another SSH session:

```bash
curl -s http://127.0.0.1:5000/api/status | jq
```

Expected output (order may vary):

```json
{
  "ok": true,
  "pins": [4,5,6,9,10,11,12,13,16,17,19,20,21,22,26,27],
  "allow_mode": "list",
  "deny": [2,3,14,15],
  "backend": "pigpio",
  "pigpio_connected": true
}
```

Test a few relays to confirm they toggle as expected (replace `{pin}` with any allowed pin):

```bash
curl -s -X POST http://127.0.0.1:5000/api/pin/{pin}/on | jq
curl -s -X POST http://127.0.0.1:5000/api/pin/{pin}/off | jq
```

Each command should activate the matching relay LED and then turn it back off.

---

## 6. Systemd service

Create `/etc/systemd/system/sprinkler.service` so the controller starts automatically on boot:

```bash
sudo tee /etc/systemd/system/sprinkler.service >/dev/null <<'UNIT'
[Unit]
Description=Sprinkler Controller API
After=network-online.target pigpiod.service
Wants=network-online.target

[Service]
Type=simple
User=tybuell
WorkingDirectory=/srv/sprinkler-controller
EnvironmentFile=/srv/sprinkler-controller/.env
ExecStart=/srv/sprinkler-controller/.venv/bin/uvicorn sprinkler.app:app --host 0.0.0.0 --port ${SPRINKLER_API_PORT}
Restart=on-failure
StandardOutput=append:/var/log/sprinkler.log
StandardError=append:/var/log/sprinkler.log

[Install]
WantedBy=multi-user.target
UNIT
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable sprinkler.service
sudo systemctl restart sprinkler.service
sudo systemctl status sprinkler.service --no-pager
```

Tail logs when troubleshooting:

```bash
sudo journalctl -u sprinkler.service -f
```

Whenever the backend code changes:

1. Deploy updated files (SCP or git pull).
2. **Do not** overwrite `.env`.
3. Restart the service with `sudo systemctl restart sprinkler.service`.
4. Re-run the `/api/status` check.

---

## 7. iOS app pairing checklist

1. Open the Sprink! app on your iPhone.
2. In Settings → Target Address, set `http://sprinkler.local:5000` (or use the Pi's IP).
3. Tap **Run Health Check** — it should report `Connected`.
4. On the main controls screen you should now see exactly 16 zones, matching the wiring table.

If the health check fails, verify:

- The Pi responds to `ping sprinkler.local` from your phone's network.
- `/api/status` returns `pigpio_connected: true` on the Pi.
- The `.env` allow list has no typos.

---

## 8. Optional: Bonjour/mDNS advertisement

To let the iOS app discover the controller automatically, enable Avahi:

```bash
sudo apt install -y avahi-daemon avahi-utils
sudo tee /etc/avahi/services/sprinkler.service >/dev/null <<'XML'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h Sprinkler</name>
  <service>
    <type>_sprinkler._tcp</type>
    <port>5000</port>
    <txt-record>path=/api/status</txt-record>
  </service>
</service-group>
XML
sudo systemctl restart avahi-daemon
```

Validate from a Mac on the same network:

```bash
dns-sd -B _sprinkler._tcp
```

---

## 9. Next steps

* Finish documenting any zone names in the UI (use the `/api/pin/{pin}/name` endpoint).
* Review FastAPI logging now that the service is stable; adjust log rotation in `/var/log/sprinkler.log` if needed.
* With connectivity confirmed, we can move on to polishing the iOS UI without risking backend regressions.

---

### Quick reference commands

```bash
# Transfer files from Mac
scp localfile.txt tybuell@sprinkler:/srv/sprinkler-controller

# SSH into the Pi
ssh tybuell@sprinkler

# Restart the controller after deploying new code
sudo systemctl restart sprinkler.service

# Check live logs
sudo journalctl -u sprinkler.service -f
```

Keep this README up to date as wiring or configuration changes so future updates remain effortless.
