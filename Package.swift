// swift-tools-version: 5.8
#if canImport(PackageDescription) && !os(iOS)
import PackageDescription

/// Swift Package manifest that exposes the connectivity components of the
/// Sprinkler mobile app as a standalone library so they can be reused by other
/// targets (for example the Raspberry Pi test harness). Wrapping the manifest
/// in a conditional check keeps Xcode from trying to compile the file when the
/// iOS application target builds. The additional `!os(iOS)` guard prevents the
/// compiler from attempting to import the SwiftPM only `PackageDescription`
/// module when archiving for device, which previously resulted in a
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
                "Resources",
                "Views",
                "ViewModels/DashboardViewModel.swift",
                "SprinklerMobileApp.swift",
                "Stores/SprinklerStore.swift",
                "Stores/PinCatalogMerger.swift",
                "Data/APIClient.swift",
                "Utils/Color+Theme.swift",
                "Utils/Theme.swift",
                "Data/PinDTO.swift",
                "Data/SSLPinningDelegate.swift",
                "Data/ScheduleDraft.swift",
                "Data/Schedule.swift",
                "Data/SchedulePersistence.swift",
                "Data/GPIOCatalog.swift",
                "Utils/KeychainStorage.swift",
                "Utils/SkeletonView.swift",
                "Data/ScheduleDTO.swift",
                "Data/HTTPClient.swift",
                "Data/RainDTO.swift",
                "Data/StatusDTO.swift",
                "Data/AuthenticationController.swift",
                "Data/EmptyResponse.swift",
                "Utils/Toast.swift",
                "Stores/ConnectivityState+Presentation.swift"
            ],
            sources: [
                "Models/ConnectionTestLog.swift",
                "Models/DiscoveredDevice.swift",
                "Data/APIError.swift",
                "Data/AuthenticationProtocols.swift",
                "Services/HealthService.swift",
                "Services/BonjourDiscoveryService.swift",
                "Stores/ConnectivityStore.swift",
                "Utils/ControllerConfig.swift",
                "Utils/URLNormalize.swift",
                "Utils/Validators.swift",
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
