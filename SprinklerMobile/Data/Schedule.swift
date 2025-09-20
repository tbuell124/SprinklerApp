import Foundation

/// Domain representation of a watering schedule that can be persisted locally and
/// synchronised with the Raspberry Pi controller when network connectivity is
/// available. The struct purposefully mirrors the controller payload so the same
/// value can be encoded to JSON for offline storage or REST payloads.
struct Schedule: Identifiable, Codable, Hashable {
    /// Describes a single step in a watering sequence.
    struct Step: Codable, Hashable {
        var pin: Int
        var durationMinutes: Int
    }

    var id: String
    var name: String
    var startTime: String
    var days: [String]
    var isEnabled: Bool
    var sequence: [Step]
    /// Last time the schedule was modified locally.
    var lastModified: Date
    /// Timestamp of the last successful controller sync. `nil` means the
    /// schedule has never been uploaded to the controller.
    var lastSyncedAt: Date?

    init(id: String = UUID().uuidString,
         name: String = "",
         startTime: String = Schedule.defaultStartTime,
         days: [String] = Schedule.defaultDays,
         isEnabled: Bool = true,
         sequence: [Step] = [],
         lastModified: Date = Date(),
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.days = Schedule.orderedDays(from: days)
        self.isEnabled = isEnabled
        self.sequence = sequence
        self.lastModified = lastModified
        self.lastSyncedAt = lastSyncedAt
    }

    /// Returns the total runtime for the schedule by summing every sequence step.
    var totalDurationMinutes: Int {
        sequence.reduce(into: 0) { partialResult, step in
            partialResult += max(step.durationMinutes, 0)
        }
    }

    /// Indicates whether local changes still need to be synchronised to the controller.
    var needsSync: Bool {
        guard let lastSyncedAt else { return true }
        return lastSyncedAt < lastModified
    }

    /// Provides an ordered representation of weekdays that matches the UI and backend expectations.
    static func orderedDays(from days: [String]) -> [String] {
        let lowercased = Set(days.map { $0.lowercased() })
        return defaultDays.filter { lowercased.contains($0.lowercased()) }
    }

    /// Sanitises the name to ensure we never persist schedules with whitespace-only titles.
    var sanitizedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns a write payload compatible with the existing controller API.
    func writePayload() -> ScheduleWritePayload {
        let normalisedSequence = sequence.map { step in
            ScheduleWritePayload.Step(pin: step.pin,
                                       durationMinutes: max(step.durationMinutes, 0))
        }
        let fallbackDuration = normalisedSequence.first?.durationMinutes ?? Schedule.defaultDurationMinutes
        return ScheduleWritePayload(name: sanitizedName,
                                    durationMinutes: fallbackDuration,
                                    startTime: startTime,
                                    days: days.isEmpty ? nil : Schedule.orderedDays(from: days),
                                    isEnabled: isEnabled,
                                    sequence: normalisedSequence)
    }
}

extension Schedule {
    static let defaultStartTime = "06:00"
    static let defaultDurationMinutes = 10
    static let defaultDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

extension Schedule {
    /// Creates a persisted schedule from the controller DTO. Any controller-provided
    /// data is considered authoritative, so both `lastModified` and `lastSyncedAt`
    /// are stamped with the time of decoding.
    init(dto: ScheduleDTO, defaultPins: [PinDTO]) {
        let resolvedSequence = dto.resolvedSequence(defaultPins: defaultPins)
        let now = Date()
        self.init(id: dto.id,
                  name: dto.name ?? "",
                  startTime: dto.startTime ?? Schedule.defaultStartTime,
                  days: dto.days ?? Schedule.defaultDays,
                  isEnabled: dto.isEnabled ?? true,
                  sequence: resolvedSequence.map { Step(pin: $0.pin, durationMinutes: $0.durationMinutes) },
                  lastModified: now,
                  lastSyncedAt: now)
    }

    /// Converts the persisted representation back into a DTO for use with
    /// components that still rely on the legacy type.
    func dto() -> ScheduleDTO {
        ScheduleDTO(id: id,
                    name: sanitizedName,
                    startTime: startTime,
                    days: days,
                    isEnabled: isEnabled,
                    durationMinutes: sequence.first?.durationMinutes,
                    sequence: sequence.map { step in
                        ScheduleSequenceItemDTO(pin: step.pin, durationMinutes: step.durationMinutes)
                    })
    }
}

