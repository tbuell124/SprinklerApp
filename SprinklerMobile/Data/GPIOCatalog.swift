import Foundation

/// Catalog of GPIO pins that the iOS client can safely expose for zone control.
///
/// The Raspberry Pi exposes twenty-eight addressable GPIO pins (BCM 0-27) that
/// the irrigation controller can map to sprinkler zones. The installer in this
/// deployment has every available output wired, so the catalog must expose the
/// full set so the iOS client can toggle each solenoid.
struct GPIOCatalog {
    /// Default zones that ship with a fresh installation of the controller.
    ///
    /// The mobile client needs a predictable set of pins so the UI can render
    /// something useful before it has a chance to talk to the Raspberry Pi.
    /// Present every usable GPIO so the placeholder state mirrors the fully
    /// wired system.
    private static let defaultZonePins: [Int] = Array(0...27)

    /// GPIO pin numbers that are electrically safe to expose in the user
    /// interface.  The controller hardware only drives pins 0-27 (BCM
    /// numbering), so publish that subset for both placeholder data and any
    /// validation logic.
    static let safeOutputPins: [Int] = defaultZonePins

    /// Creates human friendly placeholder models for each default irrigation
    /// zone.  These placeholders mirror the data the API will eventually
    /// provide once the client successfully communicates with the controller.
    static func makeDefaultPins() -> [PinDTO] {
        defaultZonePins.enumerated().map { index, pin in
            PinDTO(pin: pin,
                   name: "Zone \(index + 1)",
                   isActive: false,
                   isEnabled: true)
        }
    }
}
