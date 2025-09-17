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

    init(pins: [PinDTO]? = nil,
         schedules: [ScheduleDTO]? = nil,
         scheduleGroups: [ScheduleGroupDTO]? = nil,
         rain: RainDTO? = nil,
         version: String? = nil,
         lastUpdated: Date? = nil) {
        self.pins = pins
        self.schedules = schedules
        self.scheduleGroups = scheduleGroups
        self.rain = rain
        self.version = version
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedPins = try? container.decode([PinDTO].self, forKey: .pins) {
            pins = decodedPins
        } else if let legacyPins = try container.decodeIfPresent([Int].self, forKey: .pins) {
            pins = legacyPins.map { PinDTO(pin: $0, name: nil, isActive: nil, isEnabled: nil) }
        } else {
            pins = nil
        }

        schedules = try container.decodeIfPresent([ScheduleDTO].self, forKey: .schedules)
        scheduleGroups = try container.decodeIfPresent([ScheduleGroupDTO].self, forKey: .scheduleGroups)
        rain = try container.decodeIfPresent(RainDTO.self, forKey: .rain)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
    }
}
