import SwiftUI

struct PinsListView: View {
    let pins: [PinDTO]
    let isLoading: Bool
    let onToggle: (PinDTO, Bool) -> Void
    let onReorder: (IndexSet, Int) -> Void

    init(pins: [PinDTO], isLoading: Bool = false, onToggle: @escaping (PinDTO, Bool) -> Void, onReorder: @escaping (IndexSet, Int) -> Void) {
        self.pins = pins
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
                ForEach(pins) { pin in
                    PinRowView(pin: pin, onToggle: onToggle)
                }
                .onMove(perform: onReorder)
            }
        }
    }
}
