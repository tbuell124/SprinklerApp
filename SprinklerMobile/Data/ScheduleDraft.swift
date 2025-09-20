import Foundation

struct ScheduleDraft: Identifiable, Equatable {
    var id: String
    var name: String
    var runTimeMinutes: Int
    var startTime: String
    var days: [String]
    var isEnabled: Bool

    init(id: String = UUID().uuidString,
         name: String = "",
         runTimeMinutes: Int = Schedule.defaultDurationMinutes,
         startTime: String = Schedule.defaultStartTime,
         days: [String] = Schedule.defaultDays,
         isEnabled: Bool = true,
         pins _: [PinDTO] = []) {
        self.id = id
        self.name = name
        self.runTimeMinutes = max(runTimeMinutes, 0)
        self.startTime = startTime
        self.days = Schedule.orderedDays(from: days)
        self.isEnabled = isEnabled
    }

    init(schedule: Schedule, pins _: [PinDTO] = []) {
        self.id = schedule.id
        self.name = schedule.name
        self.runTimeMinutes = max(schedule.runTimeMinutes, 0)
        self.startTime = schedule.startTime
        if schedule.days.isEmpty {
            self.days = Schedule.defaultDays
        } else {
            self.days = Schedule.orderedDays(from: schedule.days)
        }
        self.isEnabled = schedule.isEnabled
    }

    var payload: ScheduleWritePayload {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduleWritePayload(id: id,
                                    name: trimmedName.isEmpty ? nil : trimmedName,
                                    durationMinutes: max(runTimeMinutes, 0),
                                    startTime: startTime,
                                    days: days.isEmpty ? nil : Schedule.orderedDays(from: days),
                                    isEnabled: isEnabled)
    }

    var schedule: Schedule {
        return Schedule(id: id,
                         name: name,
                         runTimeMinutes: max(runTimeMinutes, 0),
                         startTime: startTime,
                         days: days,
                         isEnabled: isEnabled,
                         lastModified: Date(),
                         lastSyncedAt: nil)
    }
}

/// Payload used when creating or updating a schedule via the controller API.
struct ScheduleWritePayload: Encodable {
    let id: String
    let name: String?
    let durationMinutes: Int
    let startTime: String
    let days: [String]?
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
    }
}
