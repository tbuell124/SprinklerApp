import Foundation

struct ScheduleDraft: Identifiable, Equatable {
    struct Step: Identifiable, Equatable {
        var id: UUID
        var pin: Int
        var durationMinutes: Int

        init(id: UUID = UUID(), pin: Int, durationMinutes: Int) {
            self.id = id
            self.pin = pin
            self.durationMinutes = durationMinutes
        }
    }

    var id: String
    var name: String
    var startTime: String
    var days: [String]
    var isEnabled: Bool
    var sequence: [Step]

    init(id: String = UUID().uuidString,
         name: String = "",
         startTime: String = "06:00",
         days: [String] = ScheduleDraft.defaultDays,
         isEnabled: Bool = true,
         sequence: [Step] = [],
         pins: [PinDTO] = []) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.days = ScheduleDraft.orderedDays(from: days)
        self.isEnabled = isEnabled
        if sequence.isEmpty {
            let resolvedPins = pins.filter { $0.isEnabled ?? true }
            let seeds = resolvedPins.isEmpty ? pins : resolvedPins
            self.sequence = seeds.map { Step(pin: $0.pin, durationMinutes: Self.defaultDurationMinutes) }
        } else {
            self.sequence = sequence
        }
    }

    init(schedule: ScheduleDTO, pins: [PinDTO] = []) {
        self.id = schedule.id
        self.name = schedule.name ?? ""
        self.startTime = schedule.startTime ?? "06:00"
        if let specifiedDays = schedule.days, !specifiedDays.isEmpty {
            self.days = ScheduleDraft.orderedDays(from: specifiedDays)
        } else {
            self.days = ScheduleDraft.defaultDays
        }
        self.isEnabled = schedule.isEnabled ?? true
        let resolvedSequence = schedule.resolvedSequence(defaultPins: pins)
        if resolvedSequence.isEmpty, let firstPin = pins.first {
            self.sequence = [Step(pin: firstPin.pin,
                                   durationMinutes: schedule.durationMinutes ?? Self.defaultDurationMinutes)]
        } else {
            self.sequence = resolvedSequence.map { item in
                Step(pin: item.pin, durationMinutes: item.durationMinutes)
            }
        }
    }

    var payload: ScheduleWritePayload {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSequence = sequence.map { step -> Step in
            var copy = step
            copy.durationMinutes = max(copy.durationMinutes, 0)
            return copy
        }
        let fallbackDuration = sanitizedSequence.first?.durationMinutes ?? Self.defaultDurationMinutes
        return ScheduleWritePayload(name: trimmedName.isEmpty ? nil : trimmedName,
                                    durationMinutes: fallbackDuration,
                                    startTime: startTime,
                                    days: days.isEmpty ? nil : ScheduleDraft.orderedDays(from: days),
                                    isEnabled: isEnabled,
                                    sequence: sanitizedSequence.map { step in
                                        ScheduleWritePayload.Step(pin: step.pin,
                                                                  durationMinutes: step.durationMinutes)
                                    })
    }

    mutating func addSteps(for pins: [PinDTO]) {
        let existingPins = Set(sequence.map(\.pin))
        let defaultDuration = sequence.first?.durationMinutes ?? Self.defaultDurationMinutes
        let additions = pins.filter { !existingPins.contains($0.pin) }
        sequence.append(contentsOf: additions.map { pin in
            Step(pin: pin.pin, durationMinutes: defaultDuration)
        })
    }

    mutating func addStep(for pin: PinDTO) {
        guard !sequence.contains(where: { $0.pin == pin.pin }) else { return }
        let defaultDuration = sequence.first?.durationMinutes ?? Self.defaultDurationMinutes
        sequence.append(Step(pin: pin.pin, durationMinutes: defaultDuration))
    }

    mutating func removeSteps(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            guard sequence.indices.contains(offset) else { continue }
            sequence.remove(at: offset)
        }
    }

    mutating func moveSteps(from offsets: IndexSet, to destination: Int) {
        let items = offsets.compactMap { index -> Step? in
            guard sequence.indices.contains(index) else { return nil }
            return sequence[index]
        }
        removeSteps(at: offsets)
        let adjustedDestination = destination - offsets.filter { $0 < destination }.count
        let clampedDestination = max(0, min(adjustedDestination, sequence.count))
        sequence.insert(contentsOf: items, at: clampedDestination)
    }

    private static let defaultDurationMinutes = 10
    static let defaultDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func orderedDays(from days: [String]) -> [String] {
        let lowercased = Set(days.map { $0.lowercased() })
        return defaultDays.filter { lowercased.contains($0.lowercased()) }
    }
}

/// Payload used when creating or updating a schedule via the controller API.
struct ScheduleWritePayload: Encodable {
    let name: String?
    let durationMinutes: Int
    let startTime: String
    let days: [String]?
    let isEnabled: Bool
    let sequence: [Step]

    struct Step: Encodable, Equatable {
        let pin: Int
        let durationMinutes: Int

        enum CodingKeys: String, CodingKey {
            case pin
            case durationMinutes = "duration"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name
        case durationMinutes = "duration"
        case startTime = "start_time"
        case days
        case isEnabled = "is_enabled"
        case sequence
    }
}
