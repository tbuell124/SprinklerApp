import Foundation

struct ScheduleDTO: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let startTime: String?
    let days: [String]?
    let isEnabled: Bool?
    let durationMinutes: Int?
    let sequence: [ScheduleSequenceItemDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
        case durationMinutes = "duration"
        case sequence
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
    /// Resolves the effective sequence for this schedule, falling back to applying the
    /// legacy single duration to the provided default pins when the backend has not yet
    /// transitioned to per-pin durations.
    /// - Parameter defaultPins: Pins sourced from the controller. Enabled pins are
    ///   preferred, but the method will gracefully fall back to the provided list to
    ///   ensure every legacy schedule continues to run.
    /// - Returns: Ordered sequence of pin/duration pairs.
    func resolvedSequence(defaultPins: [PinDTO]) -> [ScheduleSequenceItemDTO] {
        if let sequence, !sequence.isEmpty {
            return sequence
        }

        let normalizedDuration = max(durationMinutes ?? 0, 0)
        guard !defaultPins.isEmpty else { return [] }

        let enabledPins = defaultPins.filter { $0.isEnabled ?? true }
        let pinsToUse = enabledPins.isEmpty ? defaultPins : enabledPins
        return pinsToUse.map { pin in
            ScheduleSequenceItemDTO(pin: pin.pin, durationMinutes: normalizedDuration)
        }
    }

    /// Calculates the total runtime for the schedule by summing each sequence step.
    /// - Parameter defaultPins: Pins used to infer the sequence for legacy payloads.
    /// - Returns: Total number of minutes the schedule will run.
    func totalDuration(defaultPins: [PinDTO]) -> Int {
        resolvedSequence(defaultPins: defaultPins)
            .reduce(0) { partialResult, item in
                partialResult + max(item.durationMinutes, 0)
            }
    }
}
