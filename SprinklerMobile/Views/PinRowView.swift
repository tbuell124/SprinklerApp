import SwiftUI

struct PinRowView: View {
    let pin: PinDTO
    let onToggle: (PinDTO, Bool) -> Void

    var body: some View {
        HStack {
            Text(pin.displayName)
                .font(.headline)
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
