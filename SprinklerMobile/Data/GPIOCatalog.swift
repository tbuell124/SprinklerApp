import Foundation

/// Catalog of sprinkler zones that the mobile client can expose before it
/// successfully downloads the definitive configuration from the controller.
///
/// The project originally targeted all twenty-eight Raspberry Pi pins, but the
/// production wiring only connects four solenoids. Publishing just those
/// sprinklers keeps the placeholder UI realistic for installers and avoids
/// suggesting unsupported outputs.
struct GPIOCatalog {
    /// Default GPIO configuration that mirrors the four production sprinkler
    /// zones connected to the Raspberry Pi controller.
    private static let defaultPins: [PinDTO] = [
        PinDTO(pin: 0, name: "Zone 1", isActive: false, isEnabled: true),
        PinDTO(pin: 1, name: "Zone 2", isActive: false, isEnabled: true),
        PinDTO(pin: 2, name: "Zone 3", isActive: false, isEnabled: true),
        PinDTO(pin: 3, name: "Zone 4", isActive: false, isEnabled: true)
    ]

    /// GPIO pin numbers that are safe for the UI to expose.
    static let safeOutputPins: [Int] = defaultPins.map(\.pin)

    /// Creates placeholder pins for the UI when no controller data is
    /// available.
    static func makeDefaultPins() -> [PinDTO] {
        defaultPins
    }
}
