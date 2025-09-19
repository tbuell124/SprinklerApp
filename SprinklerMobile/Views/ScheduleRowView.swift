import SwiftUI

struct ScheduleRowView: View {
    @EnvironmentObject private var store: SprinklerStore
    let schedule: ScheduleDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.name ?? "Schedule")
                .font(.headline)
            HStack(spacing: 12) {
                if let durationText = durationLabelText {
                    Label(durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let start = schedule.startTime {
                    Label(start, systemImage: "alarm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let days = schedule.days, !days.isEmpty {
                    Label(days.joined(separator: ", "), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sequenceText = sequenceSummaryText {
                    Label(sequenceText, systemImage: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var durationLabelText: String? {
        let totalDuration = schedule.totalDuration(defaultPins: store.pins)
        guard totalDuration > 0 else { return nil }
        return "\(totalDuration) min"
    }

    private var sequenceSummaryText: String? {
        let sequence = schedule.resolvedSequence(defaultPins: store.pins)
        guard !sequence.isEmpty else { return nil }

        let pinLookup = Dictionary(uniqueKeysWithValues: store.pins.map { ($0.pin, $0) })
        let segments = sequence.map { item -> String in
            let pinName = pinLookup[item.pin]?.name ?? "Pin \(item.pin)"
            return "\(pinName) – \(item.durationMinutes)m"
        }

        if segments.count <= 3 {
            return segments.joined(separator: ", ")
        }

        let prefix = segments.prefix(3).joined(separator: ", ")
        return prefix + ", …"
    }
}
