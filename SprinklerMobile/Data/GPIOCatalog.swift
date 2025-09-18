import Foundation

/// Catalog of GPIO pins that the iOS client can safely expose for zone control.
///
/// The Raspberry Pi exposes several pins that are reserved for power, ground,
/// or board identification. Those are intentionally omitted so the UI only
/// allows renaming and enabling pins that are usable as digital outputs for
/// irrigation relays.
struct GPIOCatalog {
    /// Stable, sorted list of GPIO numbers that are safe to drive as outputs.
    ///
    /// The list is based on the Broadcom (BCM) numbering scheme and excludes
    /// pins reserved for power, ground, or the ID EEPROM bus. SPI and I²C
    /// capable pins are included because they can still be used as general
    /// purpose outputs when those peripherals are not in use on the controller.
    static let safeOutputPins: [Int] = [
        2,  // GPIO2  - SDA (I²C) but fully usable as a digital output
        3,  // GPIO3  - SCL (I²C) but fully usable as a digital output
        4,  // GPIO4  - commonly used for general purpose output
        5,  // GPIO5  - safe digital channel
        6,  // GPIO6  - safe digital channel
        7,  // GPIO7  - can double as SPI CE1
        8,  // GPIO8  - can double as SPI CE0
        9,  // GPIO9  - can double as SPI MISO
        10, // GPIO10 - can double as SPI MOSI
        11, // GPIO11 - can double as SPI SCLK
        12, // GPIO12 - supports PWM
        13, // GPIO13 - supports PWM
        14, // GPIO14 - UART TX (usable if serial console disabled)
        15, // GPIO15 - UART RX (usable if serial console disabled)
        16, // GPIO16 - general purpose
        17, // GPIO17 - general purpose
        18, // GPIO18 - supports PWM
        19, // GPIO19 - supports PWM
        20, // GPIO20 - general purpose
        21, // GPIO21 - general purpose
        22, // GPIO22 - general purpose
        23, // GPIO23 - general purpose
        24, // GPIO24 - general purpose
        25, // GPIO25 - general purpose
        26, // GPIO26 - general purpose
        27  // GPIO27 - general purpose
    ]

    /// Creates placeholder pin models for every safe GPIO so the UI can display
    /// the full catalog before the controller responds with live data.
    static func makeDefaultPins() -> [PinDTO] {
        safeOutputPins.map { pin in
            PinDTO(pin: pin,
                   name: nil,
                   isActive: nil,
                   isEnabled: false)
        }
    }
}
