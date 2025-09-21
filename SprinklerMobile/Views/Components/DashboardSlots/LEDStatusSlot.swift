import SwiftUI

struct LEDStatusSlot: View {
    let pins: [PinDTO]
    let connectivityState: ConnectivityState
    let lastSeenTime: Date?
    @State private var animatingPins: Set<Int> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GPIO Status")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
                connectionChip
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(pins, id: \.pin) { pin in
                    LEDIndicator(pin: pin, isAnimating: animatingPins.contains(pin.pin))
                        .onChange(of: pin.isActive) { _, _ in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                animatingPins.insert(pin.pin)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                animatingPins.remove(pin.pin)
                            }
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GPIO Status Grid")
    }
    
    private var connectionChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            
            Text(connectionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(connectionText)")
    }
    
    private var connectionColor: Color {
        switch connectivityState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
    
    private var connectionText: String {
        switch connectivityState {
        case .connected:
            return "Pi Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            if let lastSeen = lastSeenTime {
                let interval = Date().timeIntervalSince(lastSeen)
                if interval < 60 {
                    return "Last seen: \(Int(interval))s ago"
                } else {
                    return "Last seen: \(Int(interval / 60))m ago"
                }
            }
            return "Disconnected"
        }
    }
}

struct LEDIndicator: View {
    let pin: PinDTO
    let isAnimating: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill((pin.isActive ?? false) ? .green : .gray.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke((pin.isActive ?? false) ? .green : .clear, lineWidth: 2)
                        .scaleEffect(isAnimating ? 1.3 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                )
                .accessibilityLabel("GPIO \(pin.pin)")
                .accessibilityValue((pin.isActive ?? false) ? "On" : "Off")
            
            Text("\(pin.pin)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
