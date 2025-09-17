import SwiftUI

struct RainCardView: View {
    let rain: RainDTO?
    let onSubmit: (Bool, Int?) -> Void

    @State private var isActive: Bool = false
    @State private var durationHours: Int = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isActive) {
                Text("Rain Delay")
                    .font(.headline)
            }
            .toggleStyle(.switch)

            Stepper(value: $durationHours, in: 1...72, step: 1) {
                Text("Duration: \(durationHours)h")
                    .font(.subheadline)
            }
            .disabled(!isActive)

            if let endsAt = rain?.endsAt {
                Text("Ends: \(endsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                let duration = isActive ? durationHours : nil
                onSubmit(isActive, duration)
            } label: {
                Text("Apply")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .onChange(of: rain, perform: sync(with:))
        .onAppear {
            sync(with: rain)
        }
    }

    private func sync(with rain: RainDTO?) {
        isActive = rain?.isActive ?? false
        if let hours = rain?.durationHours, hours > 0 {
            durationHours = hours
        }
    }
}
