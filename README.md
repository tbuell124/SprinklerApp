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
