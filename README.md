SprinklerApp Setup Guide
========================

This repository contains the SwiftUI iOS client that talks to your Raspberry Pi sprinkler controller.

- If you need a comprehensive step-by-step walkthrough for provisioning a brand-new Raspberry Pi (including all SSH commands, Python backend code, and systemd automation), read the dedicated guide in [`RaspberryPiSetup.md`](RaspberryPiSetup.md).
- The sections below continue to focus on the iOS application, its architecture, and high-level backend integration notes.

## Raspberry Pi Backend Quick Reference

The Raspberry Pi backend exposes `/status` and `/zone/(on|off)/{zone}`. To keep the hardware safe:
- (Optional) If you add the compat routes below, `/api/status`, `/api/pins`, and `/api/pin/{pin}` will also work.

- Only the following 16 BCM GPIO pins are permitted to toggle sprinkler relays: `4, 5, 6, 9, 10, 11, 12, 13, 16, 17, 19, 20, 21, 22, 26, 27`.
- The `.env` file should include:
  ```dotenv
  SPRINKLER_GPIO_ALLOW=12,16,20,21,26,19,13,6,5,11,9,10,22,27,17,4
  SPRINKLER_GPIO_DENY=2,3,14,15
  ```
  This configuration blocks I²C and UART pins by default while still allowing the 16 wired relays.
- After updating the environment file run:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl restart sprinkler-api.service
  sudo systemctl status sprinkler-api.service --no-pager
  ```

### Verifying the allowed pins list

1. (Optional) Install `jq` for prettier JSON in your terminal:
   ```bash
   sudo apt-get update
   sudo apt-get install -y jq
   ```
2. Inspect the backend status:
   ```bash
   TOKEN='<your token>'
   curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8000/status | jq
   # (if you add the compat shim, /api/status will also work)
   ```
   You should see exactly the 16 pins listed above under the `"pins"` key.
3. Spot-check a few relays with:
   ```bash
   curl -s -X POST -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' -d '{"minutes":1}' \
     http://127.0.0.1:8000/zone/on/1 | jq
   curl -s -X POST -H "Authorization: Bearer $TOKEN" \
     http://127.0.0.1:8000/zone/off/1 | jq
   ```
   Repeat for other pins (for example `27` or `12`) to confirm each zone toggles the correct relay.

## iOS Client Overview

The Sprink! iOS app is a modern SwiftUI application with a comprehensive 4-slot dashboard interface. Major features include:

### 🎛️ Modern 4-Slot Dashboard
- **LED Status Grid**: Compact square grid showing GPIO pin states, Pi connectivity, and rain delay status
- **Schedule Summary**: Real-time "Currently Running" and "Up Next" schedule information  
- **Pin Controls**: Collapsible, reorderable pin list with manual toggles and run timers
- **Rain Status**: Connectivity monitoring, weather integration, and automation controls

### 📅 Advanced Schedule Management
- Sequence scheduling with pin/duration pairs
- Cross-midnight schedule support (handles 24-hour wraparound)
- Drag-and-drop reordering within sequences
- Schedule duplication and deletion
- Collapsible sections for active pins

### ⚙️ Comprehensive Settings
- Pin renaming with GPIO number display
- Active/inactive pin management
- Raspberry Pi IP address configuration with connection testing
- Rain delay automation (ZIP code, threshold percentage)
- Detailed connection logs and failure reporting

### ♿ Accessibility & Modern Design
- Full Dynamic Type support with custom font scaling
- High contrast colors (4.5:1 ratio compliance)
- Comprehensive VoiceOver support with proper labels and hints
- Adaptive theming for light/dark modes
- Smooth animations and micro-interactions

### Technical Features
- Zone toggling via authenticated HTTP endpoints
- Live status monitoring and moisture lockout awareness
- Bonjour/mDNS discovery so you can find your sprinkler controller automatically on the LAN
- Modern SwiftUI patterns with MVVM architecture
- Async/await for network operations
- Comprehensive error handling

Refer to the Xcode project for the full SwiftUI implementation. When you update the backend, ensure that the API endpoints stay aligned with the iOS client expectations documented within the app source code comments.

## Networking & Discovery Notes

- The iOS client expects HTTPS or secured HTTP within your LAN. Use a VPN if accessing the controller remotely.
- Bonjour discovery relies on the Raspberry Pi advertising a `_sprinkler._tcp` service. Follow the Raspberry Pi setup guide to enable Avahi and publish the service.

## Need Help?

Open an issue or submit a pull request with reproducible steps and logs so we can help triage faster. Contributions that improve documentation, performance, or security are welcome.
