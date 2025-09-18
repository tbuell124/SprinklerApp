import Foundation

struct ScheduleDraft: Identifiable, Equatable {
    var id: String
    var name: String
    var durationMinutes: Int
    var startTime: String
    var days: [String]
    var isEnabled: Bool

    init(id: String = UUID().uuidString,
         name: String = "",
         durationMinutes: Int = 10,
         startTime: String = "06:00",
         days: [String] = [],
         isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.durationMinutes = durationMinutes
        self.startTime = startTime
        self.days = days
        self.isEnabled = isEnabled
    }

    init(schedule: ScheduleDTO) {
        self.id = schedule.id
        self.name = schedule.name ?? ""
        self.durationMinutes = schedule.durationMinutes ?? 10
        self.startTime = schedule.startTime ?? "06:00"
        self.days = schedule.days ?? []
        self.isEnabled = schedule.isEnabled ?? true
    }

    var payload: ScheduleWritePayload {
        ScheduleWritePayload(name: name.isEmpty ? nil : name,
                             durationMinutes: durationMinutes,
                             startTime: startTime,
                             days: days.isEmpty ? nil : days,
                             isEnabled: isEnabled)
    }
}

/// Payload used when creating or updating a schedule via the controller API.
struct ScheduleWritePayload: Encodable {
    let name: String?
    let durationMinutes: Int
    let startTime: String
    let days: [String]?
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
    }
}
