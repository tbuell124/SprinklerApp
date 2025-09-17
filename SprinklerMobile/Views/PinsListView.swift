import SwiftUI

struct PinsListView: View {
    let pins: [PinDTO]
    let totalPinCount: Int
    let isLoading: Bool
    let onToggle: (PinDTO, Bool) -> Void
    let onReorder: (IndexSet, Int) -> Void

    private var enabledPins: [PinDTO] {
        pins.filter { $0.isEnabled ?? true }
    }

    private var hiddenPins: [PinDTO] {
        pins.filter { !($0.isEnabled ?? true) }
    }

    init(pins: [PinDTO],
         totalPinCount: Int,
         isLoading: Bool = false,
         onToggle: @escaping (PinDTO, Bool) -> Void,
         onReorder: @escaping (IndexSet, Int) -> Void) {
        self.pins = pins
        self.totalPinCount = totalPinCount
        self.isLoading = isLoading
        self.onToggle = onToggle
        self.onReorder = onReorder
    }

    var body: some View {
        Section("Zones") {
            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    PinRowSkeleton()
                }
            } else if pins.isEmpty {
                if totalPinCount == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.down.forward")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Pins Available")
                            .font(.headline)
                        Text("Pull to refresh once the controller is reachable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Active Pins")
                            .font(.headline)
                        Text("Enable pins from Settings to manage them here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                }
            } else {
                if enabledPins.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Enabled Pins")
                            .font(.headline)
                        Text("Enable pins from Settings to control them here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                } else {
                    ForEach(enabledPins) { pin in
                        PinRowView(pin: pin, onToggle: onToggle)
                    }
                    .onMove(perform: onReorder)
                }

                if !hiddenPins.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hidden Pins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, enabledPins.isEmpty ? 0 : 12)

                        ForEach(hiddenPins) { pin in
                            PinRowView(pin: pin, onToggle: onToggle)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
