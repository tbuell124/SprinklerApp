import SwiftUI

struct ScheduleRowView: View {
    let schedule: ScheduleDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.name ?? "Schedule")
                .font(.headline)
            HStack(spacing: 12) {
                if let duration = schedule.durationMinutes {
                    Label("\(duration) min", systemImage: "clock")
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
            }
        }
        .padding(.vertical, 6)
    }
}
