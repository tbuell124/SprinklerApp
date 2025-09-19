// swift-tools-version: 5.8
#if canImport(PackageDescription)
import PackageDescription

/// Swift Package manifest that exposes the connectivity components of the
/// Sprinkler mobile app as a standalone library so they can be reused by other
/// targets (for example the Raspberry Pi test harness). Wrapping the manifest
/// in a `canImport` check keeps Xcode from trying to compile the file when the
/// iOS application target builds, which previously resulted in a
/// `No such module 'PackageDescription'` compiler error.
let package = Package(
    name: "SprinklerConnectivity",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SprinklerConnectivity", targets: ["SprinklerConnectivity"])
    ],
    targets: [
        .target(
            name: "SprinklerConnectivity",
            path: "SprinklerMobile",
            exclude: [
                "Data",
                "Resources",
                "Utils",
                "Views",
                "SprinklerMobileApp.swift",
                "Stores/SprinklerStore.swift"
            ],
            sources: [
                "Models/DiscoveredDevice.swift",
                "Services/HealthChecker.swift",
                "Services/BonjourDiscoveryService.swift",
                "Stores/ConnectivityStore.swift",
                "ViewModels/DiscoveryViewModel.swift"
            ]
        ),
        .testTarget(
            name: "SprinklerConnectivityTests",
            dependencies: ["SprinklerConnectivity"],
            path: "Tests/SprinklerConnectivityTests"
        )
    ]
)
#endif
