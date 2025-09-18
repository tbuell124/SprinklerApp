// swift-tools-version: 5.8
import PackageDescription

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
