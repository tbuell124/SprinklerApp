import SwiftUI

struct ScheduleSummarySlot: View {
    let currentlyRunning: RunningSchedule?
    let upNext: UpcomingSchedule?
    let isEmpty: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedules")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            if isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let running = currentlyRunning {
                        currentlyRunningView(running)
                    }
                    
                    if let upcoming = upNext {
                        upNextView(upcoming)
                    }
                    
                    if currentlyRunning == nil && upNext == nil {
                        Text("No schedules active")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("No schedules currently active")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule Summary")
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("No schedules today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No schedules today")
    }
    
    private func currentlyRunningView(_ running: RunningSchedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                
                Text("Currently Running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(running.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(running.zone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(running.formattedTime)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Currently running: \(running.name) on \(running.zone), \(running.formattedTime) remaining")
    }
    
    private func upNextView(_ upcoming: UpcomingSchedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                
                Text("Up Next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            HStack {
                Text(upcoming.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(upcoming.formattedETA)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(upcoming.name) at \(upcoming.formattedETA)")
    }
}
