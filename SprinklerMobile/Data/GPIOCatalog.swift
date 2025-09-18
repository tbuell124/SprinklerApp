import Foundation

/// Compatibility shim that preserves the previous `GPIOCatalog` API while the
/// project transitions to the new static helpers defined on `PinDTO`.
struct GPIOCatalog {
    /// GPIO pin numbers that are safe for the UI to expose.
    static let safeOutputPins: [Int] = PinDTO.sprinklerSafeOutputPins

    /// Creates placeholder pins for the UI when no controller data is
    /// available.
    static func makeDefaultPins() -> [PinDTO] {
        PinDTO.makeDefaultSprinklerPins()
    }
}
