import Foundation

struct ScheduleGroupDTO: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let isActive: Bool?
    let scheduleIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case scheduleIds = "schedule_ids"
    }
}
