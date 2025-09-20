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
        // The order mirrors the Raspberry Pi mapping defined in
        // `backend/app.py` and `backend/sprinkler_service.py`. Keeping the
        // sequence identical ensures the iOS placeholders line up with the
        // physical relay wiring (zone 1 = GPIO 12, ..., zone 16 = GPIO 4)
        // while the device waits for a live `/status` payload.
        PinDTO(pin: 12, name: "Zone 1", isActive: false, isEnabled: true),
        PinDTO(pin: 16, name: "Zone 2", isActive: false, isEnabled: true),
        PinDTO(pin: 20, name: "Zone 3", isActive: false, isEnabled: true),
        PinDTO(pin: 21, name: "Zone 4", isActive: false, isEnabled: true),
        PinDTO(pin: 26, name: "Zone 5", isActive: false, isEnabled: true),
        PinDTO(pin: 19, name: "Zone 6", isActive: false, isEnabled: true),
        PinDTO(pin: 13, name: "Zone 7", isActive: false, isEnabled: true),
        PinDTO(pin: 6, name: "Zone 8", isActive: false, isEnabled: true),
        PinDTO(pin: 5, name: "Zone 9", isActive: false, isEnabled: true),
        PinDTO(pin: 11, name: "Zone 10", isActive: false, isEnabled: true),
        PinDTO(pin: 9, name: "Zone 11", isActive: false, isEnabled: true),
        PinDTO(pin: 10, name: "Zone 12", isActive: false, isEnabled: true),
        PinDTO(pin: 22, name: "Zone 13", isActive: false, isEnabled: true),
        PinDTO(pin: 27, name: "Zone 14", isActive: false, isEnabled: true),
        PinDTO(pin: 17, name: "Zone 15", isActive: false, isEnabled: true),
        PinDTO(pin: 4, name: "Zone 16", isActive: false, isEnabled: true)
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
