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
                if let daysText = daysLabelText {
                    Label(daysText, systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private var daysLabelText: String? {
        guard let days = schedule.days, !days.isEmpty else {
            return "Daily"
        }

        let normalized = days.map { $0.lowercased() }
        let fullWeek = Set(ScheduleDraft.defaultDays.map { $0.lowercased() })
        if Set(normalized) == fullWeek {
            return "Daily"
        }

        return ScheduleDraft.orderedDays(from: days).joined(separator: ", ")
    }
}
