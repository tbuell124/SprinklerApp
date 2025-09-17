import Foundation

struct RainDTO: Codable, Equatable {
    let isActive: Bool?
    let endsAt: Date?
    let durationHours: Int?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case endsAt = "ends_at"
        case durationHours = "duration_hours"
    }
}
