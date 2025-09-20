import SwiftUI

struct ScheduleRowView: View {
    @EnvironmentObject private var store: SprinklerStore
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.sanitizedName ?? "Schedule")
                .font(.headline)
            HStack(spacing: 12) {
                if let durationText = durationLabelText {
                    Label(durationText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(schedule.startTime, systemImage: "alarm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        let totalDuration = schedule.totalDurationMinutes
        guard totalDuration > 0 else { return nil }
        return "\(totalDuration) min"
    }

    private var daysLabelText: String? {
        guard !schedule.days.isEmpty else {
            return "Daily"
        }

        let normalized = schedule.days.map { $0.lowercased() }
        let fullWeek = Set(Schedule.defaultDays.map { $0.lowercased() })
        if Set(normalized) == fullWeek {
            return "Daily"
        }

        return Schedule.orderedDays(from: schedule.days).joined(separator: ", ")
    }
}
