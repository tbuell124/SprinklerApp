import SwiftUI

struct RainStatusSlot: View {
    let rainDelayUntil: Date?
    let isWeatherAvailable: Bool
    let onDisableRainDelay: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rain Status")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            if let delayUntil = rainDelayUntil {
                activeRainDelayView(until: delayUntil)
            } else {
                inactiveRainDelayView
            }
            
            if !isWeatherAvailable {
                weatherUnavailableView
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rain Status")
    }
    
    private func activeRainDelayView(until: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                
                Text("Rain Delay Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Until \(formattedTime(until))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Schedules paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Disable") {
                    Task {
                        await onDisableRainDelay()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Disable rain delay")
            }
        }
        .padding(12)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rain delay active until \(formattedTime(until)). Schedules are paused.")
    }
    
    private var inactiveRainDelayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                
                Text("No Rain Delay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            Text("Schedules running normally")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No rain delay active. Schedules running normally.")
    }
    
    private var weatherUnavailableView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            
            Text("Weather unavailable—using manual delay only")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather data unavailable, using manual rain delay only")
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
