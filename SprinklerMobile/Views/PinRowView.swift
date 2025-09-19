import SwiftUI

struct PinRowView: View {
    let pin: PinDTO
    let onToggle: (PinDTO, Bool) -> Void

    private var canToggle: Bool {
        pin.isEnabled ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pin.displayName)
                    .font(.appButton)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { pin.isActive ?? false },
                    set: { newValue in
                        if canToggle {
                            onToggle(pin, newValue)
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel(Text("Toggle \(pin.displayName)"))
                .accessibilityValue(Text((pin.isActive ?? false) ? "On" : "Off"))
                .disabled(!canToggle)
            }

            if !canToggle {
                Text("Enable in Settings to control this zone.")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .opacity(canToggle ? 1 : 0.45)
    }
}
