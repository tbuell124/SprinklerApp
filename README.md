SprinklerApp Setup Guide
========================

This repository contains the SwiftUI iOS client that talks to your Raspberry Pi sprinkler controller.

- If you need a comprehensive step-by-step walkthrough for provisioning a brand-new Raspberry Pi (including all SSH commands, Python backend code, and systemd automation), read the dedicated guide in [`RaspberryPiSetup.md`](RaspberryPiSetup.md).
- The sections below continue to focus on the iOS application, its architecture, and high-level backend integration notes.

## iOS Client Overview

The Sprink! iOS app communicates with a FastAPI backend hosted on your Raspberry Pi. Major features include:

- Zone toggling via authenticated HTTP endpoints
- Live status monitoring and moisture lockout awareness
- Bonjour/mDNS discovery so you can find your sprinkler controller automatically on the LAN

Refer to the Xcode project for the full SwiftUI implementation. When you update the backend, ensure that the API endpoints stay aligned with the iOS client expectations documented within the app source code comments.

## Networking & Discovery Notes

- The iOS client expects HTTPS or secured HTTP within your LAN. Use a VPN if accessing the controller remotely.
- Bonjour discovery relies on the Raspberry Pi advertising a `_sprinkler._tcp` service. Follow the Raspberry Pi setup guide to enable Avahi and publish the service.

## Need Help?

Open an issue or submit a pull request with reproducible steps and logs so we can help triage faster. Contributions that improve documentation, performance, or security are welcome.
