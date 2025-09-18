// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "SprinklerConnectivity",
    platforms: [
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
                "Stores",
                "ViewModels",
                "Utils",
                "Views",
                "SprinklerMobileApp.swift"
            ],
            sources: [
                "Services/HealthChecker.swift",
                "Services/BonjourDiscoveryService.swift",
                "Store/ConnectivityStore.swift"
            ]
        ),
        .testTarget(
            name: "SprinklerConnectivityTests",
            dependencies: ["SprinklerConnectivity"],
            path: "Tests/SprinklerConnectivityTests"
        )
    ]
)
