import Foundation

/// Catalog of sprinkler zones that the mobile client can expose before it
/// successfully downloads the definitive configuration from the controller.
///
/// The production controller is wired to eight relay outputs that drive the
/// irrigation solenoids. Publishing just those sprinklers keeps the placeholder
/// UI realistic for installers and prevents the app from surfacing pins that
/// are either unsafe to toggle or connected to other peripherals on the Pi.
struct GPIOCatalog {
    /// Default GPIO configuration that mirrors the eight production sprinkler
    /// zones connected to the Raspberry Pi controller. The numbers are the
    /// Broadcom (BCM) pin identifiers used by the backend and pigpio.
    private static let defaultPins: [PinDTO] = [
        PinDTO(pin: 4, name: "Zone 1", isActive: false, isEnabled: true),
        PinDTO(pin: 17, name: "Zone 2", isActive: false, isEnabled: true),
        PinDTO(pin: 27, name: "Zone 3", isActive: false, isEnabled: true),
        PinDTO(pin: 22, name: "Zone 4", isActive: false, isEnabled: true),
        PinDTO(pin: 5, name: "Zone 5", isActive: false, isEnabled: true),
        PinDTO(pin: 6, name: "Zone 6", isActive: false, isEnabled: true),
        PinDTO(pin: 13, name: "Zone 7", isActive: false, isEnabled: true),
        PinDTO(pin: 19, name: "Zone 8", isActive: false, isEnabled: true)
    ]

    /// GPIO pin numbers that are safe for the UI to expose.
    static let safeOutputPins: [Int] = defaultPins.map(\.pin)

    /// Creates placeholder pins for the UI when no controller data is
    /// available.
    static func makeDefaultPins() -> [PinDTO] {
        defaultPins
    }
}
