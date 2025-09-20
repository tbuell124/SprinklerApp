import Foundation

struct ScheduleDTO: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let runTimeMinutes: Int?
    let startTime: String?
    let days: [String]?
    let isEnabled: Bool?
    let sequence: [ScheduleSequenceItemDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case runTimeMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
        case sequence
    }

    init(id: String,
         name: String?,
         runTimeMinutes: Int?,
         startTime: String?,
         days: [String]?,
         isEnabled: Bool?,
         sequence: [ScheduleSequenceItemDTO]? = nil) {
        self.id = id
        self.name = name
        self.runTimeMinutes = runTimeMinutes
        self.startTime = startTime
        self.days = days
        self.isEnabled = isEnabled
        self.sequence = sequence
    }
}

/// Describes a single step in a watering sequence, pairing a physical pin with its
/// runtime. The backend encodes these values using the `duration` key to preserve
/// compatibility with the previous payload shape.
struct ScheduleSequenceItemDTO: Codable, Hashable {
    let pin: Int
    let durationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case pin
        case durationMinutes = "duration"
    }
}

extension ScheduleDTO {
    /// Resolves the effective runtime for both the modern and legacy payloads.
    /// - Returns: Total number of minutes the schedule should run.
    func resolvedRunTimeMinutes() -> Int {
        if let runTimeMinutes {
            return max(runTimeMinutes, 0)
        }

        return sequence?.reduce(0) { partialResult, item in
            partialResult + max(item.durationMinutes, 0)
        } ?? 0
    }
}
