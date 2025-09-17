# SprinklerApp

Sprinkler System on Raspberry Pi.

## iOS Client Project Setup

An accompanying native iOS app should be created in Xcode by the integrator. **Do not generate the Xcode project from this repository.** Instead, create a new SwiftUI iOS 16+ project in Xcode and configure it according to the design and networking requirements documented in the product brief. Once the project shell exists, bring the Swift source files and configuration described in the brief into that Xcode workspace manually.

Key reminders when setting up the Xcode project:

- Ensure App Transport Security allows local network loads (e.g., set `NSAllowsArbitraryLoadsInLocalNetworks` to `YES`).
- Target iOS 16 or later.
- Add the Swift packages or dependencies required by the client code during Xcode configuration.
- Store the Target IP in `UserDefaults` and wire the networking stack to respect that setting.

Any additional app configuration should also be handled directly within Xcode by the integrator after creating the project.

## SwiftUI Client Code Layout

The `SprinklerMobile` folder contains the SwiftUI source files, models, and configuration required for the native iOS application. After creating the Xcode project, copy these files into your project (preserving the folder grouping if desired) and add them to the target.

```
SprinklerMobile/
  SprinklerMobileApp.swift        // App entry point and tab navigation
  Models/                         // Codable DTOs matching the Raspberry Pi API
  Networking/                     // HTTP client, API client, and error types
  State/                          // ObservableObject stores for app state & settings
  Utils/                          // Validation helpers and toast presentation
  Views/                          // SwiftUI views for Dashboard, Schedules, Settings
  Resources/Info.plist            // ATS snippet allowing local network HTTP
```

The app is organized into three primary tabs (Dashboard, Schedules, Settings) and communicates exclusively with the existing Raspberry Pi HTTP endpoints. Update the target IP address from the Settings tab to point at the controller on your LAN, then build and run the project from Xcode to interact with the sprinkler system.
