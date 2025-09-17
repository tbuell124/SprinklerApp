import Foundation

struct ScheduleDTO: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let durationMinutes: Int?
    let startTime: String?
    let days: [String]?
    let isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
    }
}
