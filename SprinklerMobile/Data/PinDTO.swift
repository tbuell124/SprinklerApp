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
