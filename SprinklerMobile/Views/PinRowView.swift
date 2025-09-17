import SwiftUI

struct PinRowView: View {
    let pin: PinDTO
    let onToggle: (PinDTO, Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(pin.name ?? "Pin \(pin.pin)")
                    .font(.headline)
                Text("GPIO \(pin.pin)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { pin.isActive ?? false },
                set: { newValue in onToggle(pin, newValue) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
