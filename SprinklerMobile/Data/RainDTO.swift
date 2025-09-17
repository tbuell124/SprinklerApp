import Foundation

struct RainDTO: Codable, Equatable {
    let isActive: Bool?
    let endsAt: Date?
    let durationHours: Int?
    let chancePercent: Int?
    let thresholdPercent: Int?
    let zipCode: String?
    let automationEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case endsAt = "ends_at"
        case durationHours = "duration_hours"
        case chancePercent = "chance_percent"
        case thresholdPercent = "threshold_percent"
        case zipCode = "zip_code"
        case automationEnabled = "automation_enabled"
    }
}
