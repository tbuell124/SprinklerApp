import Foundation

struct StatusDTO: Codable {
    let pins: [PinDTO]?
    let schedules: [ScheduleDTO]?
    let scheduleGroups: [ScheduleGroupDTO]?
    let rain: RainDTO?
    let version: String?
    let lastUpdated: Date?

    enum CodingKeys: String, CodingKey {
        case pins
        case schedules
        case scheduleGroups = "schedule_groups"
        case rain
        case version
        case lastUpdated = "last_updated"
    }
}
