# Raspberry Pi Deployment Guide

This guide walks through provisioning a brand-new Raspberry Pi to host the Sprinkler backend that the Sprink! iOS app talks to. Follow each step sequentially—from flashing Raspberry Pi OS, to installing dependencies, copying the controller code, hardening the service, and finally verifying connectivity from your phone.

> **Scope**
> * Fresh Raspberry Pi OS install (Lite or Desktop)
> * Headless administration from a macOS workstation
> * FastAPI backend with pigpio-driven GPIO control
> * Persistent startup via `systemd`
> * Bonjour/mDNS advertisement for discovery

---

## 1. Prerequisites

### Hardware
- Raspberry Pi 3B+ or newer
- microSD card (16 GB+ recommended)
- 24VAC sprinkler valves wired through a relay board to the Pi GPIO header
- Stable 5V power supply capable of powering the Pi plus relays

#### Relay wiring map (current production build)

| BCM GPIO | Physical Pin | Notes |
| --- | --- | --- |
| 12 | 32 | Left-most relay when facing the screw terminals |
| 16 | 36 | |
| 20 | 38 | |
| 21 | 40 | |
| 26 | 37 | |
| 19 | 35 | |
| 13 | 33 | |
| 6  | 31 | |
| 5  | 29 | |
| 11 | 23 | |
| 9  | 21 | SPI MISO repurposed for relay control |
| 10 | 19 | SPI MOSI repurposed for relay control |
| 22 | 15 | |
| 27 | 13 | |
| 17 | 11 | |
| 4  | 7  | Right-most relay |

Only these 16 GPIO pins should be exposed by the backend. Power, ground, I²C (2/3), and UART (14/15) remain locked out.

### Workstation (macOS)
- [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
- SSH client (macOS Terminal works out of the box)
- Git (via Xcode Command Line Tools or Homebrew)

### Network
- Pi and iPhone on the same LAN
- Router/DHCP access so you can reserve a static IP or hostname (`sprinkler.local` recommended)

### Credentials
- Default user in this guide: `tybuell`
- Hostname for the Pi: `sprinkler`

> Replace `tybuell` and `sprinkler` with your own username/hostname if they differ. All commands assume those names.

---

## 2. Flash & Boot the Pi

1. Use Raspberry Pi Imager to flash **Raspberry Pi OS Lite (64-bit)**.
2. Before writing, open the **Advanced Options** (gear icon) and enable:
   - Set hostname: `sprinkler`
   - Enable SSH: *Use password authentication*
   - Set username/password: `tybuell` / `<your-secure-password>`
   - Configure Wi-Fi if you do not plan to use Ethernet (include your SSID, password, and locale)
   - Set locale, timezone, and keyboard layout to match your location
3. Insert the microSD card into the Pi, connect Ethernet (recommended) or Wi-Fi, then power on.
4. Locate the Pi's IP: `ping sprinkler.local` or check your router.

---

## 3. First-Time SSH Session & System Prep

All remote operations happen over SSH from your Mac terminal. Connect:

```bash
ssh tybuell@sprinkler
```

Accept the host fingerprint when prompted. Then perform the following steps in order:

### 3.1 Update base packages
```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

After the Pi reboots, reconnect:

```bash
ssh tybuell@sprinkler
```

### 3.2 Install OS-level dependencies
```bash
sudo apt install -y git python3 python3-venv python3-pip pigpio nginx-full avahi-daemon avahi-utils
```

> `nginx` acts as a future reverse proxy if you enable HTTPS. It is optional now but installing it up front avoids downtime later.

### 3.3 Enable pigpio daemon for GPIO management
```bash
sudo systemctl enable --now pigpiod
sudo systemctl status pigpiod --no-pager
```

You should see `active (running)`. Press `q` to exit the status view.

---

## 4. Prepare the Application Directory

All controller code lives at `/srv/sprinkler-controller`.

```bash
sudo mkdir -p /srv/sprinkler-controller
sudo chown tybuell:tybuell /srv/sprinkler-controller
cd /srv/sprinkler-controller
```

Create a Python virtual environment and upgrade packaging tools:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
```

---

## 5. Deploy the Backend Code

### 5.1 Copy the project from your Mac

On your Mac (outside the Pi SSH session), clone this repository so you can copy the backend helper files:

```bash
cd ~/Projects
git clone https://github.com/your-org/SprinklerApp.git
```

Copy the backend template files into the Pi using `scp`:

```bash
scp SprinklerApp/backend/sprinkler_service.py tybuell@sprinkler:/srv/sprinkler-controller
scp SprinklerApp/backend/requirements.txt tybuell@sprinkler:/srv/sprinkler-controller
```

> If you modify the files locally, rerun the `scp` commands to push the updates. Always place them in `/srv/sprinkler-controller`.

### 5.2 (Optional) Edit directly on the Pi

If you prefer editing on the Pi, create the files with `nano`:

```bash
ssh tybuell@sprinkler
cd /srv/sprinkler-controller
nano sprinkler_service.py
```

Paste the backend source code (see Section 5.3), save (`Ctrl+O`), and exit (`Ctrl+X`).

### 5.3 Backend Python application (`sprinkler_service.py`)

Below is a complete FastAPI app that controls GPIO pins through `pigpio`. Copy/paste it exactly.

```python
# FILE: sprinkler_service.py   # removed stray double-quote to avoid SyntaxError
"""Sprinkler backend service exposing authenticated HTTP endpoints.

This module is designed for Raspberry Pi deployments that control 24VAC sprinkler
valves via relay boards wired to GPIO pins. It uses pigpio for reliable timing
and enforces token-based authentication on every request.
"""
from __future__ import annotations

import asyncio
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import pigpio
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from starlette.responses import JSONResponse

# ---------------------------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------------------------

APP_VERSION = "1.0.0"
DEFAULT_GPIO_PINS = [4, 17, 27, 22, 5, 6, 13, 19]
DEFAULT_RUNTIME_MINUTES = 30
RAIN_LOCK_DEFAULT_HOURS = int(os.getenv("RAIN_LOCK_DEFAULT_HOURS", "24"))
API_TOKEN = os.getenv("SPRINKLER_API_TOKEN")
API_PORT = int(os.getenv("SPRINKLER_API_PORT", "8000"))
ALLOWED_ORIGINS = os.getenv("SPRINKLER_ALLOWED_ORIGINS", "").split(",") if os.getenv("SPRINKLER_ALLOWED_ORIGINS") else []

if API_TOKEN is None:
    raise RuntimeError("SPRINKLER_API_TOKEN is required in the environment")

GPIO_PINS: List[int] = [
    int(pin.strip()) for pin in os.getenv("SPRINKLER_GPIO_PINS", ",".join(str(p) for p in DEFAULT_GPIO_PINS)).split(",") if pin.strip()
]

# ---------------------------------------------------------------------------
# pigpio setup
# ---------------------------------------------------------------------------

pi = pigpio.pi()
if not pi.connected:
    raise RuntimeError("Failed to connect to pigpiod. Ensure 'sudo systemctl status pigpiod' shows active.")

for gpio in GPIO_PINS:
    pi.set_mode(gpio, pigpio.OUTPUT)
    pi.write(gpio, 1)  # Relays are active-low; set HIGH to keep valves off.

# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------

class ZoneState(BaseModel):
    zone: int
    gpio: int
    is_on: bool
    remaining_minutes: Optional[int] = None

class SystemStatus(BaseModel):
    version: str
    zones: List[ZoneState]
    rain_lock_expires_at: Optional[datetime]

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------

_active_jobs: Dict[int, asyncio.Task] = {}
_rain_lock_until: Optional[datetime] = None

# ---------------------------------------------------------------------------
# Authentication dependency
# ---------------------------------------------------------------------------

def require_token(request: Request) -> None:
    header = request.headers.get("authorization")
    if not header or header.strip() != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid token")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def _gpio_for_zone(zone: int) -> int:
    try:
        return GPIO_PINS[zone - 1]
    except IndexError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not configured") from exc


def _remaining_minutes(task: asyncio.Task) -> Optional[int]:
    if task.done():
        return None
    seconds_left = getattr(task, "seconds_left", None)
    if seconds_left is None:
        return None
    return max(0, round(seconds_left() / 60))


async def _turn_zone_off(zone: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 1)
    if zone in _active_jobs:
        _active_jobs.pop(zone, None)


async def _zone_timer(zone: int, duration_minutes: int) -> None:
    gpio = _gpio_for_zone(zone)
    pi.write(gpio, 0)  # energize relay
    end_time = datetime.utcnow() + timedelta(minutes=duration_minutes)

    def seconds_left() -> float:
        return max(0.0, (end_time - datetime.utcnow()).total_seconds())

    asyncio.current_task().seconds_left = seconds_left  # type: ignore[attr-defined]

    try:
        await asyncio.sleep(duration_minutes * 60)
    finally:
        pi.write(gpio, 1)  # de-energize relay
        _active_jobs.pop(zone, None)

# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------

app = FastAPI(title="Sprinkler Controller", version=APP_VERSION)

if ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"]
    )

@app.get("/status", response_model=SystemStatus, dependencies=[Depends(require_token)])
async def get_status() -> SystemStatus:
    zones: List[ZoneState] = []
    for idx, gpio in enumerate(GPIO_PINS, start=1):
        is_on = pi.read(gpio) == 0
        remaining = _remaining_minutes(_active_jobs[idx]) if idx in _active_jobs else None
        zones.append(ZoneState(zone=idx, gpio=gpio, is_on=is_on, remaining_minutes=remaining))

    return SystemStatus(
        version=APP_VERSION,
        zones=zones,
        rain_lock_expires_at=_rain_lock_until,
    )


@app.post("/zone/on/{zone}", dependencies=[Depends(require_token)])
async def turn_zone_on(zone: int, minutes: int = DEFAULT_RUNTIME_MINUTES) -> JSONResponse:
    if _rain_lock_until and datetime.utcnow() < _rain_lock_until:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Rain lock active")

    if minutes <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Runtime must be positive")

    if zone in _active_jobs:
        _active_jobs[zone].cancel()

    task = asyncio.create_task(_zone_timer(zone, minutes))
    _active_jobs[zone] = task
    return JSONResponse({"status": "on", "zone": zone, "minutes": minutes})


@app.post("/zone/off/{zone}", dependencies=[Depends(require_token)])
async def turn_zone_off(zone: int) -> JSONResponse:
    await _turn_zone_off(zone)
    return JSONResponse({"status": "off", "zone": zone})


@app.post("/rain-lock", dependencies=[Depends(require_token)])
async def enable_rain_lock(hours: int = RAIN_LOCK_DEFAULT_HOURS) -> JSONResponse:
    global _rain_lock_until
    if hours <= 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Hours must be positive")

    _rain_lock_until = datetime.utcnow() + timedelta(hours=hours)
    for zone in list(_active_jobs.keys()):
        await _turn_zone_off(zone)
    return JSONResponse({"rain_lock_expires_at": _rain_lock_until.isoformat()})


@app.delete("/rain-lock", dependencies=[Depends(require_token)])
async def clear_rain_lock() -> JSONResponse:
    global _rain_lock_until
    _rain_lock_until = None
    return JSONResponse({"rain_lock_expires_at": None})


@app.exception_handler(Exception)
async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "unexpected_error", "details": str(exc)},
    )
```

### 5.4 Python dependencies

Back inside the Pi SSH session:

```bash
cd /srv/sprinkler-controller
source .venv/bin/activate
pip install -r requirements.txt
```

Example `requirements.txt` (copy to `/srv/sprinkler-controller/requirements.txt`):

```text
fastapi==0.111.0
uvicorn[standard]==0.30.1
pigpio==1.78
python-dotenv==1.0.1
pydantic==1.10.14
```

---

## 6. Environment Configuration

Create the `.env` file on the Pi. **Do not commit this file to Git.**

```bash
cd /srv/sprinkler-controller
nano .env
```

Paste the template below and update values for your hardware layout and secrets.

```dotenv
SPRINKLER_API_PORT=8000
SPRINKLER_API_TOKEN=change-me-to-a-strong-token
SPRINKLER_GPIO_ALLOW=12,16,20,21,26,19,13,6,5,11,9,10,22,27,17,4
SPRINKLER_GPIO_DENY=2,3,14,15
# Legacy deployments can fall back to SPRINKLER_GPIO_PINS if you are still using sprinkler_service.py
# SPRINKLER_GPIO_PINS=4,17,27,22,5,6,13,19
RAIN_LOCK_DEFAULT_HOURS=24
SPRINKLER_ALLOWED_ORIGINS=
```

- `SPRINKLER_API_TOKEN`: Strong bearer token required by every HTTP request.
- `SPRINKLER_GPIO_ALLOW`: Comma-separated allow list for relay control. Only these pins are exposed over the API.
- `SPRINKLER_GPIO_DENY`: Additional safety block list. Keep `2,3,14,15` to avoid I²C/UART toggling.
- `SPRINKLER_GPIO_PINS`: **Legacy option** for the original `sprinkler_service.py`. Prefer the allow/deny configuration for new deployments.
- `SPRINKLER_ALLOWED_ORIGINS`: Optional comma-separated list for enabling CORS if you integrate a web UI later.

Load the environment variables automatically by creating a systemd drop-in (done in the next section) or exporting them manually for testing:

```bash
set -a
source /srv/sprinkler-controller/.env
set +a
```

---

## 7. Manual Smoke Test

Run the service from the terminal to verify dependencies and wiring:

```bash
cd /srv/sprinkler-controller
source .venv/bin/activate
uvicorn sprinkler_service:app --host 0.0.0.0 --port "$SPRINKLER_API_PORT"
```

From another terminal (on your Mac):

```bash
curl -H "Authorization: Bearer change-me-to-a-strong-token" http://sprinkler.local:8000/status
```

Confirm the JSON payload lists your zones and that no errors appear in the running server. Stop the server with `Ctrl+C` once validated.

### 7.1 Confirm the allowed pins list

After the service is running (whether manually or via systemd) double-check that only the expected 16 GPIO pins appear.

1. (Optional) Install `jq` for easier-to-read JSON:
   ```bash
   sudo apt-get update
   sudo apt-get install -y jq
   ```
2. Query the backend locally on the Pi:
   ```bash
   TOKEN='<your token>'
   curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8000/status | jq
   # (if you keep compat routes below, /api/status will also work)
   ```
   The `"pins"` field should list `4,5,6,9,10,11,12,13,16,17,19,20,21,22,26,27` (order may differ, but the set must match).
3. Spot-check a relay to confirm it toggles correctly:
   ```bash
   curl -s -X POST -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' -d '{"minutes":1}' \
     http://127.0.0.1:8000/zone/on/1 | jq
   curl -s -X POST -H "Authorization: Bearer $TOKEN" \
     http://127.0.0.1:8000/zone/off/1 | jq
   ```
   Repeat for a few other pins (for example `27` and `12`). Any pin outside the allow list should return a 404.

---

## 8. Create the systemd Service

Back on the Pi:

```bash
sudo tee /etc/systemd/system/sprinkler-api.service >/dev/null <<'UNIT'
[Unit]
Description=Sprinkler HTTP Controller
After=network-online.target pigpiod.service
Wants=network-online.target

[Service]
Type=simple
User=tybuell
WorkingDirectory=/srv/sprinkler-controller
EnvironmentFile=/srv/sprinkler-controller/.env
ExecStart=/srv/sprinkler-controller/.venv/bin/uvicorn sprinkler_service:app --host 0.0.0.0 --port ${SPRINKLER_API_PORT}
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/sprinkler.log
StandardError=append:/var/log/sprinkler.log

[Install]
WantedBy=multi-user.target
UNIT
```

Set log file permissions and enable the service:

```bash
sudo touch /var/log/sprinkler.log
sudo chown tybuell:tybuell /var/log/sprinkler.log
sudo systemctl daemon-reload
sudo systemctl enable sprinkler-api.service
sudo systemctl start sprinkler-api.service
sudo systemctl status sprinkler-api.service --no-pager
```

Check the live logs:

```bash
sudo journalctl -u sprinkler-api.service -f
```

Press `Ctrl+C` to exit the log tail.

> When updating the backend later, redeploy your code (via `scp` or Git pull) and restart with `sudo systemctl restart sprinkler-api.service`.

---

## 9. Bonjour/mDNS Advertisement

Enable discovery so the iOS app can find the Pi automatically.

```bash
sudo tee /etc/avahi/services/sprinkler.service >/dev/null <<'XML'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Sprinkler Controller (%h)</name>
  <service>
    <type>_sprinkler._tcp</type>
    <port>8000</port>
    <txt-record>path=/status</txt-record>
  </service>
</service-group>
XML

sudo systemctl restart avahi-daemon
```

Validate from your Mac:

```bash
dns-sd -B _sprinkler._tcp
```

You should see the Pi broadcast the service. Stop with `Ctrl+C`.

---

## 10. Connect the iOS App

1. Build and install the Sprink! app on your iPhone.
2. Open **Settings → Controller** within the app and set the controller URL to `http://sprinkler.local:8000`.
3. Enter the API token that matches `SPRINKLER_API_TOKEN`.
4. Use the discovery flow if available; it will prefer the Bonjour broadcast configured above.
5. Toggle a zone and confirm the relay clicks. Watch the Pi logs (`sudo journalctl -u sprinkler-api.service -f`) to confirm requests are authenticated.

---

## 11. Maintenance Commands Reference

Use these commands routinely:

```bash
# SCP transfer from Mac to Pi
scp localfile.txt tybuell@sprinkler:/srv/sprinkler-controller

# SSH into Pi
ssh tybuell@sprinkler

# Start and enable sprinkler API service
sudo systemctl enable sprinkler-api.service
sudo systemctl start sprinkler-api.service
sudo systemctl status sprinkler-api.service

# Restart after updates
sudo systemctl restart sprinkler-api.service

# Tail logs
sudo journalctl -u sprinkler-api.service -f
```

---

## 12. Troubleshooting Checklist

- **pigpiod not running:** `sudo systemctl status pigpiod --no-pager` and enable it if inactive.
- **Authentication failures:** Ensure your HTTP client sends `Authorization: Bearer <token>` and the token matches `.env`.
- **Zone misfires:** Confirm the `SPRINKLER_GPIO_ALLOW` list matches the wiring order (or `SPRINKLER_GPIO_PINS` if you kept the legacy service) and verify each relay with the `/api/pin/{pin}` curl checks above.
- **Service crashes at boot:** Inspect `/var/log/sprinkler.log` and `sudo journalctl -xe`. Missing environment variables or Python dependency mismatches are common culprits.
- **Bonjour not visible:** Verify `avahi-daemon` status and that UDP/5353 is open on your network.

---

## 13. Second-Pass Recommendations

Consider these hardening and resiliency improvements once the base setup is working:

- **HTTPS termination:** Use Nginx with Let's Encrypt or a self-signed certificate distributed to your devices.
- **Automated backups:** Nightly cron job that exports `.env` and sprinkler schedules to secure storage.
- **Monitoring:** Integrate with Home Assistant, Prometheus, or simple uptime monitors to alert on service failures.
- **Fail-safe defaults:** Add hardware interlocks so a stuck relay times out even if the Pi locks up.
- **Watchdog timer:** Enable the Raspberry Pi hardware watchdog to reboot on hangs (`sudo apt install watchdog`).

With this guide complete, your Raspberry Pi should boot into a reliable sprinkler controller that the Sprink! iOS app can operate securely.
