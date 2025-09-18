import Foundation

struct PinDTO: Codable, Identifiable, Hashable {
    var id: Int { pin }

    let pin: Int
    var name: String?
    var isActive: Bool?
    var isEnabled: Bool?

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "GPIO \(pin)" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case pin
        case name
        case isActive = "is_active"
        case isEnabled = "is_enabled"
    }
}

extension PinDTO {
    /// Static catalog that mirrors the physical relay wiring on the Raspberry Pi
    /// controller. These pins drive the irrigation solenoids in production and
    /// provide a realistic placeholder list before the mobile client downloads
    /// live configuration data from the backend.
    static let defaultSprinklerCatalog: [PinDTO] = [
        PinDTO(pin: 4, name: "Zone 1", isActive: false, isEnabled: true),
        PinDTO(pin: 17, name: "Zone 2", isActive: false, isEnabled: true),
        PinDTO(pin: 27, name: "Zone 3", isActive: false, isEnabled: true),
        PinDTO(pin: 22, name: "Zone 4", isActive: false, isEnabled: true),
        PinDTO(pin: 5, name: "Zone 5", isActive: false, isEnabled: true),
        PinDTO(pin: 6, name: "Zone 6", isActive: false, isEnabled: true),
        PinDTO(pin: 13, name: "Zone 7", isActive: false, isEnabled: true),
        PinDTO(pin: 19, name: "Zone 8", isActive: false, isEnabled: true)
    ]

    /// Convenience accessor that exposes just the safe-to-drive GPIO pin numbers
    /// for scenarios where only the numeric identifier is needed.
    static let sprinklerSafeOutputPins: [Int] = defaultSprinklerCatalog.map(\.pin)

    /// Returns a placeholder list of sprinkler pins that mirrors the production
    /// relay wiring. The UI uses this while waiting for the Pi controller to
    /// respond so installers can still preview the layout.
    static func makeDefaultSprinklerPins() -> [PinDTO] {
        defaultSprinklerCatalog
    }
}
