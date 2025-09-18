SprinklerApp Setup Guide

Control your irrigation system using a Raspberry Pi and companion iOS app.
The Pi hosts a FastAPI-based backend that exposes endpoints for GPIO-controlled valves, moisture lockouts, and scheduling, while the iOS app provides a clean interface for management.

1. Overview

This guide covers:

Installing required system packages on a fresh Raspberry Pi

Setting up the sprinkler backend service

Running it in a Python virtual environment

Installing and configuring a persistent systemd service so it starts on boot

Configuring networking for easy access

Integrating with the iOS app

Once complete, your Pi will boot up, run the sprinkler controller automatically, and be accessible by your iOS app with no further manual intervention.

### Running Tests
To run tests:
1. Open Xcode.
2. Select the scheme `Sprink!`.
3. Press `Cmd + U` to build and run tests.

Ensure that Sprinkler connectivity test files are only part of the `SprinklerConnectivityTests` target.

2. Prerequisites

Raspberry Pi OS (32- or 64-bit) installed and updated

SSH enabled (to manage from your computer)

A relay board or GPIO-connected valves wired to the Pi

Pi and iPhone connected to the same network

Your Pi’s IP address (find it via hostname -I or your router)

3. Raspberry Pi Setup
3.1 Update and reboot

Always start by updating the system:

sudo apt update
sudo apt full-upgrade -y
sudo reboot


Reconnect over SSH once the Pi reboots.

3.2 Install required packages

Install all necessary software for GPIO control, Python, and system services:

sudo apt install -y git python3 python3-venv python3-pip python3-rpi.gpio pigpio


Enable and start the pigpio daemon, which manages GPIO pins at the system level:

sudo systemctl enable --now pigpiod

3.3 Create the controller directory

We’ll store all code in /srv/sprinkler-controller for clarity:

sudo mkdir -p /srv/sprinkler-controller
sudo chown $USER:$USER /srv/sprinkler-controller
cd /srv/sprinkler-controller

3.4 Download the backend code

Clone your backend controller code here:

git clone https://github.com/your-org/sprinkler-controller.git .


If you’ve received the code as a .zip, copy its contents into this folder instead.

3.5 Create a virtual environment

Virtual environments keep your Python dependencies clean and isolated:

python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel

3.6 Install dependencies

If a requirements.txt is provided:

pip install -r requirements.txt


If not, manually install:

pip install fastapi uvicorn[standard] python-dotenv RPi.GPIO pigpio

3.7 Create a configuration file (.env)

The .env file defines runtime settings like GPIO pins and ports:

nano .env


Example contents:

SPRINKLER_API_PORT=5000
SPRINKLER_GPIO_PINS=4,17,27,22,5,6,13,19
RAIN_LOCK_DEFAULT_HOURS=24


Tip: Replace GPIO pins with the exact pins connected to your relay.

3.8 Test the application manually

Run the backend to ensure it works before automating it:

source /srv/sprinkler-controller/.venv/bin/activate
uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000


Open another terminal (or Safari on your phone) and test:

http://<PI_IP>:5000/api/status


You should see JSON output like:

{"ok":true,"pins":[4,17,27,22,5,6,13,19],"backend":"pigpio"}


Stop the process with CTRL+C.

3.9 Create a systemd service

This will automatically start the sprinkler API on boot and keep it running.

Create and edit the service file:

sudo nano /etc/systemd/system/sprinkler.service


Paste the following:

[Unit]
Description=Sprinkler Controller API
After=network-online.target pigpiod.service
Wants=network-online.target

[Service]
Type=simple
User=tybuell
Group=tybuell
WorkingDirectory=/srv/sprinkler-controller
EnvironmentFile=-/srv/sprinkler-controller/.env
ExecStart=/srv/sprinkler-controller/.venv/bin/uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
Restart=on-failure

[Install]
WantedBy=multi-user.target


Note: Replace tybuell with your actual username (run whoami to confirm).

3.10 Enable and start the service

Reload systemd, enable the service to run at boot, and start it now:

sudo systemctl daemon-reload
sudo systemctl enable --now pigpiod
sudo systemctl enable --now sprinkler.service


Check its status:

sudo systemctl status sprinkler.service --no-pager


Expected output:

Active: active (running)
Uvicorn running on http://0.0.0.0:5000

3.11 Verify the service

From the Pi:

curl http://127.0.0.1:5000/api/status


From your Mac or iPhone:

http://192.168.1.24:5000/api/status


You should get the same JSON as before.
If not, view logs:

journalctl -u sprinkler.service -n 50 --no-pager

4. Networking best practices

Reserve a static DHCP lease on your router for the Pi.
This ensures the Pi’s IP never changes.

Firewall (optional but recommended):
Allow only port 5000:

sudo apt install ufw
sudo ufw allow 5000/tcp
sudo ufw enable
sudo ufw status


Bonjour/mDNS (optional):
Install avahi-daemon to access your Pi via http://sprinkler.local:5000

sudo apt install avahi-daemon

5. iOS app setup

Open the iOS app and navigate to Settings → Target IP.

Enter:

http://<PI_IP>:5000


Example:

http://192.168.1.24:5000


Tap Save & Test.

If successful, you’ll see live data; if not, check:

Pi service logs (journalctl)

Firewall rules

Correct port and protocol (http:// not https://)

6. Maintenance commands
Update the backend code
cd /srv/sprinkler-controller
git pull
source .venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart sprinkler.service

Update Raspberry Pi OS
sudo apt update && sudo apt full-upgrade -y
sudo reboot

Check logs
journalctl -u sprinkler.service -f

7. Final checklist

 Pi boots and automatically runs the sprinkler API

 Port 5000 accessible from other devices on your network

 iOS app connected and working

 .env correctly configured with your zone pins

 Backups taken of /srv/sprinkler-controller and .env

Once all are checked, you now have a “set it and forget it” sprinkler controller!

8. Troubleshooting

### Build Errors

If you see “Cannot find type ConnectivityStore / DiscoveryViewModel / DiscoveredDevice”, ensure the files exist at:

- `SprinklerMobile/Store/ConnectivityStore.swift`
- `SprinklerMobile/Services/BonjourDiscoveryService.swift`
- `SprinklerMobile/ViewModels/DiscoveryViewModel.swift`

and that each file’s Target Membership includes **Sprink!**. After making changes, run **Product → Clean Build Folder** (Shift+Cmd+K) and then build again.

Issue	Likely Cause	Solution
curl works on Pi but not iPhone	Firewall or network isolation	Check UFW, router settings
ModuleNotFoundError: sprinkler	Missing or misplaced sprinkler/app.py	Ensure correct folder structure
Service shows status=217/USER	Wrong user in unit file	Edit User= to match your Pi username
iOS app says “Failed to decode…”	Wrong endpoint or JSON format	Verify URL and JSON with Safari
Nothing running on port 5000	Service didn’t start	journalctl -u sprinkler.service for logs

With these steps complete, your Raspberry Pi sprinkler controller will run continuously and require minimal upkeep.

Raspberry Pi Setup for /api/status (Phase 1)
-------------------------------------------
To let the iOS app verify connectivity, the Pi must serve an HTTP endpoint at:

```
http://<hostname-or-ip>:8000/api/status
```

that returns an HTTP 200 and a JSON object (any fields) when healthy.

Minimal Python server (FastAPI)
```
# On the Pi
sudo apt update && sudo apt install -y python3-venv git
mkdir -p /srv/sprinkler && cd /srv/sprinkler
python3 -m venv .venv
source .venv/bin/activate
pip install fastapi uvicorn

# Create app.py
cat > app.py << 'PY'
from fastapi import FastAPI
from fastapi.responses import JSONResponse
app = FastAPI()

@app.get("/api/status")
def status():
    return JSONResponse({"ok": True, "service": "sprinkler", "version": "v1"})
PY

# Run (foreground) to test:
uvicorn app:app --host 0.0.0.0 --port 8000
```

Test from a Mac (replace host as needed)
```
curl -i http://sprinkler.local:8000/api/status
# Expect: HTTP/1.1 200 OK and a JSON object like {"ok": true, ...}
```

Optional: systemd service for auto-start
```
# Create a systemd unit
sudo tee /etc/systemd/system/sprinkler.service >/dev/null <<'UNIT'
[Unit]
Description=Sprinkler API (Phase 1 status endpoint)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/srv/sprinkler
ExecStart=/srv/sprinkler/.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

# Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now sprinkler.service
sudo systemctl status sprinkler.service --no-pager
```

Notes
- No CORS config needed for native iOS apps.
- If you prefer Flask, return any 200 JSON object at /api/status.
- Keep port 8000 unless you also change the app’s default Base URL.

## Bonjour/mDNS Advertising (Phase 2)

To enable auto-discovery, the Raspberry Pi should advertise a Bonjour service. We recommend a custom service _sprinkler._tcp. on the same port used by your API (e.g., 8000).

### Install Avahi (mDNS) on Raspberry Pi
```
sudo apt update
sudo apt install -y avahi-daemon avahi-utils
sudo systemctl enable --now avahi-daemon
```

### Create a service definition for _sprinkler._tcp
```
# Create service file
sudo tee /etc/avahi/services/sprinkler.service >/dev/null <<'XML'
<?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_sprinkler._tcp</type>
    <port>8000</port>
    <txt-record>path=/api/status</txt-record>
  </service>
</service-group>
XML

# Restart Avahi
sudo systemctl restart avahi-daemon
```

If you prefer to reuse HTTP, you can instead advertise _http._tcp with a service name containing “sprinkler”, but _sprinkler._tcp avoids noise from unrelated devices.

### Verify advertisement
```
# From a Mac on the same LAN:
dns-sd -B _sprinkler._tcp
# You should see a service instance listed; then resolve it:
dns-sd -L <ServiceName> _sprinkler._tcp local
```

### Notes

- Keep the port in the service file in sync with your API server (Phase 1 default: 8000).
- The iOS app filters for services whose name or host contains “sprinkler”.

## Project Structure Update
The app now supports automatic discovery and connectivity checks.

**New folders:**
- `Models/` — Core data models like `DiscoveredDevice`.
- `Services/` — Background services such as `BonjourDiscoveryService` and `HealthChecker`.
- `ViewModels/` — ViewModels for bridging services to SwiftUI views.
- `Stores/` — Persistent app-level state like `ConnectivityStore`.

## Bonjour/mDNS Setup on Raspberry Pi
To advertise the sprinkler controller for discovery, install Avahi:

```bash
sudo apt update
sudo apt install -y avahi-daemon avahi-utils
```

Create service file at `/etc/avahi/services/sprinkler.service`:

```xml
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_sprinkler._tcp</type>
    <port>8000</port>
    <txt-record>path=/api/status</txt-record>
  </service>
</service-group>
```

Then restart:

```bash
sudo systemctl restart avahi-daemon
```

Verify:

```bash
dns-sd -B _sprinkler._tcp
```

---
