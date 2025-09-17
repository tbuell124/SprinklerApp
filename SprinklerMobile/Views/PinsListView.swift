import SwiftUI

struct PinsListView: View {
    let pins: [PinDTO]
    let onToggle: (PinDTO, Bool) -> Void
    let onReorder: (IndexSet, Int) -> Void

    var body: some View {
        Section("Zones") {
            if pins.isEmpty {
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
