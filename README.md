# SprinklerApp

SprinklerApp pairs a Raspberry Pi–based irrigation controller with a native SwiftUI client. The Pi exposes a lightweight HTTP API for monitoring moisture lockouts, toggling GPIO-controlled valves, and managing irrigation schedules. The iOS companion app consumes those endpoints to give homeowners an approachable interface for day-to-day operation.

The repository contains the SwiftUI source code that should be dropped into your own Xcode workspace. The sections below document how to bring a fresh Raspberry Pi online, deploy the controller service, and integrate the mobile client.

---

## 1. Raspberry Pi Controller Setup

The instructions assume a **fresh install of Raspberry Pi OS (32- or 64-bit) with SSH enabled**. Perform the following steps from an SSH session on the Pi.

### 1.1 Update the operating system

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Reconnect over SSH after the reboot before continuing.

### 1.2 Install base packages

```bash
sudo apt install -y git python3 python3-venv python3-pip python3-rpi.gpio pigpio
sudo systemctl enable --now pigpiod
```

These packages provide Git for pulling updates, Python tooling for the controller service, and GPIO access layers (`RPi.GPIO` and the `pigpiod` daemon) for relay control.

### 1.3 Create a runtime directory

```bash
sudo mkdir -p /srv/sprinkler-controller
sudo chown $USER:$USER /srv/sprinkler-controller
cd /srv/sprinkler-controller
```

Keeping the service under `/srv` makes it easy to manage backups and upgrades.

### 1.4 Fetch the controller code

Clone the backend controller implementation (replace the example repository URL with the actual location of your service code):

```bash
git clone https://github.com/your-org/sprinkler-controller.git .
```

If the code is delivered through another channel, copy it into the `/srv/sprinkler-controller` directory instead of cloning.

### 1.5 Create a virtual environment and install dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
pip install -r requirements.txt
```

If the project does not ship with a `requirements.txt`, install the stack manually. A typical controller uses the packages below—adjust as needed for your implementation:

```bash
pip install fastapi uvicorn[standard] python-dotenv RPi.GPIO pigpio
```

### 1.6 Configure runtime settings

Most controller services use an environment file to describe GPIO mappings, watering limits, and network settings. Create one if necessary:

```bash
cp .env.example .env  # if provided
nano .env             # otherwise create/edit manually
```

Common settings include:

- `SPRINKLER_API_PORT=5000`
- `SPRINKLER_GPIO_PINS=4,17,27,22,5,6,13,19`
- `RAIN_LOCK_DEFAULT_HOURS=24`

Consult your controller service README for the exact variables.

### 1.7 Test the application manually

```bash
source /srv/sprinkler-controller/.venv/bin/activate
uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
```

Visit `http://<raspberry-pi-ip>:5000/api/status` from another machine or use `curl` to confirm a JSON payload is returned. Stop the process with `Ctrl+C` when finished.

### 1.8 Install a systemd service

Create `/etc/systemd/system/sprinkler.service` with the following contents (adjust paths if the project structure differs):

```ini
[Unit]
Description=Sprinkler Controller API
After=network-online.target pigpiod.service
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/srv/sprinkler-controller
EnvironmentFile=/srv/sprinkler-controller/.env
ExecStart=/srv/sprinkler-controller/.venv/bin/uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sprinkler.service
sudo systemctl status sprinkler.service
```

If the status command shows the service as `active (running)`, the controller API is live on port 5000. Review `journalctl -u sprinkler.service` for troubleshooting if needed.

### 1.9 Optional hardening

- Reserve a static DHCP lease for the Raspberry Pi so its IP address does not change.
- Configure `ufw` or your network firewall to limit inbound access to the controller port.
- Set up automatic log rotation (`logrotate`) if the service writes extensive logs.

---

## 2. API Endpoints Consumed by the iOS App

The mobile client expects the following HTTP routes on the Raspberry Pi:

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET` | `/api/status` | Fetch overall controller state, including active schedules and rain delays. |
| `GET` | `/api/rain` | Retrieve the current rain delay configuration. |
| `POST` | `/api/rain` | Enable/disable rain delay with an optional duration payload. |
| `POST` | `/api/pin/{pin}/on` & `/off` | Toggle a valve (GPIO pin) on or off. |
| `POST` | `/api/pin/{pin}/name` | Rename a zone. |
| `POST` | `/api/pins/reorder` | Persist user-defined valve ordering. |
| `POST` | `/api/schedule` | Create a new irrigation schedule. |
| `POST` | `/api/schedule/{id}` | Update an existing schedule. |
| `DELETE` | `/api/schedule/{id}` | Remove a schedule. |
| `POST` | `/api/schedules/reorder` | Reorder schedules by identifier. |
| `GET` | `/api/schedule-groups` | Fetch available schedule groupings. |
| `POST` | `/api/schedule-groups` | Create a group. |
| `POST` | `/api/schedule-groups/select` | Mark the active schedule group. |
| `POST` | `/api/schedule-groups/{id}/add-all` | Add every schedule to a group. |
| `DELETE` | `/api/schedule-groups/{id}` | Delete a group. |

Ensure the backend returns JSON responses that match the DTOs defined under `SprinklerMobile/Models`.

---

## 3. iOS Client Integration

1. **Create a new Xcode project** targeting iOS 16+ using SwiftUI. Do not attempt to open this repository directly in Xcode.
2. **Copy the Swift sources** from the `SprinklerMobile` folder into the new project, preserving the folder groupings if desired.
3. **Add dependencies** referenced by the code (e.g., Combine, Swift Concurrency) through Swift Package Manager as needed.
4. **Update App Transport Security** in your project’s Info.plist to allow HTTP requests on your local network (`NSAllowsArbitraryLoadsInLocalNetworks = YES`).
5. **Configure the default controller address.** The Settings tab exposes a text field where the user enters the Raspberry Pi’s URL (for example, `http://192.168.1.50:5000`). Persisting this value is handled through `UserDefaults` in the provided store.
6. **Build and run** on a device that can reach the Raspberry Pi over the LAN. Simulator builds require the host Mac to have network access to the Pi.

Refer to the SwiftUI files inside `SprinklerMobile/Views`, `Stores`, `Data`, and `Utils` for customization points.

---

## 4. Maintenance

- Pull updates on the Raspberry Pi with:
  ```bash
  cd /srv/sprinkler-controller
  git pull
  source .venv/bin/activate
  pip install -r requirements.txt
  sudo systemctl restart sprinkler.service
  ```
- Back up `/srv/sprinkler-controller` regularly, including the `.env` file and any SQLite or JSON data files your controller stores.
- Keep Raspberry Pi OS patched by running `sudo apt update && sudo apt full-upgrade` at least monthly.

With the Raspberry Pi service online and the SwiftUI app installed on an iOS device, you can monitor and control irrigation zones securely from anywhere on your local network.





----------------
You’re super close—the error tells us exactly what’s wrong:

ModuleNotFoundError: No module named 'sprinkler'

That happens because in /srv/sprinkler-controller you cloned SprinklerApp (the iOS client), not the Pi controller backend that exposes the FastAPI app sprinkler.app:app. The service instructions expect a Python package named sprinkler/ with an app.py inside. 

README

You’ve got two ways forward. Pick one.

Option A (recommended): Use the proper backend repo

If you have (or will have) a separate backend repo (often called something like sprinkler-controller) do this:

# start clean in the controller directory
cd /srv/sprinkler-controller
rm -rf * .[^.]* 2>/dev/null || true

# clone the backend here so /srv/sprinkler-controller contains a 'sprinkler' package
git clone https://github.com/your-org/sprinkler-controller.git .
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
# if the backend has a requirements file:
pip install -r requirements.txt
# otherwise:
# pip install fastapi uvicorn[standard] python-dotenv RPi.GPIO pigpio

# (optional) create your env file
[ -f .env.example ] && cp .env.example .env || printf "SPRINKLER_API_PORT=5000\n" > .env

# quick manual test
uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000


If that runs without errors, hit it from another machine:

curl http://<PI-IP>:5000/api/status


Then create the systemd unit and enable it (see “Install the systemd service” below).

Option B: Scaffold a minimal backend right now

If you don’t have the backend repo handy yet, here’s a tiny working FastAPI app you can run immediately. It exposes /api/status and simple pin on/off routes; you can expand later.

cd /srv/sprinkler-controller
# keep your venv
[ -d .venv ] || python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip wheel
pip install fastapi uvicorn[standard] python-dotenv RPi.GPIO pigpio

# create the package structure the uvicorn command expects
mkdir -p sprinkler
cat > sprinkler/__init__.py <<'PY'
# empty
PY

cat > sprinkler/app.py <<'PY'
from fastapi import FastAPI, HTTPException
import os

app = FastAPI(title="Sprinkler Controller API")

# Try pigpio first (daemon-based), fall back to RPi.GPIO if desired
try:
    import pigpio
    PI = pigpio.pi()  # connects to local pigpiod
    if not PI.connected:
        raise RuntimeError("pigpio daemon not connected")
    USE_PIGPIO = True
except Exception:
    USE_PIGPIO = False
    try:
        import RPi.GPIO as GPIO
        GPIO.setmode(GPIO.BCM)
    except Exception:
        GPIO = None

DEFAULT_PINS = [int(p) for p in os.getenv("SPRINKLER_GPIO_PINS", "4,17,27,22,5,6,13,19").split(",")]

def set_pin(pin: int, state: bool):
    if USE_PIGPIO:
        PI.set_mode(pin, pigpio.OUTPUT)
        PI.write(pin, 1 if state else 0)
    else:
        if GPIO is None:
            raise RuntimeError("No GPIO library available")
        GPIO.setup(pin, GPIO.OUT)
        GPIO.output(pin, GPIO.HIGH if state else GPIO.LOW)

@app.get("/api/status")
def status():
    return {
        "ok": True,
        "pins": DEFAULT_PINS,
        "backend": "pigpio" if USE_PIGPIO else ("RPi.GPIO" if GPIO else "none")
    }

@app.post("/api/pin/{pin}/on")
def pin_on(pin: int):
    if pin not in DEFAULT_PINS:
        raise HTTPException(404, f"Pin {pin} not in allowed list")
    set_pin(pin, True)
    return {"pin": pin, "state": "on"}

@app.post("/api/pin/{pin}/off")
def pin_off(pin: int):
    if pin not in DEFAULT_PINS:
        raise HTTPException(404, f"Pin {pin} not in allowed list")
    set_pin(pin, False)
    return {"pin": pin, "state": "off"}
PY


Test it:

source /srv/sprinkler-controller/.venv/bin/activate
uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
# In another shell/machine:
curl http://<PI-IP>:5000/api/status


If you get JSON back, you’re good.

Install the systemd service (both options)
# create the unit file
sudo tee /etc/systemd/system/sprinkler.service >/dev/null <<'UNIT'
[Unit]
Description=Sprinkler Controller API
After=network-online.target pigpiod.service
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/srv/sprinkler-controller
EnvironmentFile=/srv/sprinkler-controller/.env
ExecStart=/srv/sprinkler-controller/.venv/bin/uvicorn sprinkler.app:app --host 0.0.0.0 --port 5000
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

# reload and enable
sudo systemctl daemon-reload
sudo systemctl enable --now sprinkler.service
sudo systemctl status sprinkler.service --no-pager


If status shows active (running), your API is live on port 5000.

Quick troubleshooting

Still seeing ModuleNotFoundError: sprinkler?
Ensure /srv/sprinkler-controller/sprinkler/app.py exists and you’re running uvicorn from /srv/sprinkler-controller (or that WorkingDirectory is set to it in the unit file).

pigpio errors (daemon not connected)
You already enabled it, but confirm:
sudo systemctl status pigpiod
If not running: sudo systemctl enable --now pigpiod

Logs
journalctl -u sprinkler.service -e -f

Port check
ss -tulpn | grep 5000

Firewall (if you added one)
Allow 5000/tcp on your LAN.

Why this happened

Per your README, the Pi service expects a backend with a sprinkler.app:app FastAPI entrypoint. You cloned the iOS client instead, so Python couldn’t import the sprinkler package. Fixing the repo location (Option A) or creating the expected package (Option B) resolves it. 

README

If you’d like, I can also tailor the .env and pin map for your specific relay board so the default endpoints line up with your zones.
