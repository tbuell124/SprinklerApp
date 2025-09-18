import SwiftUI

struct ConnectivityBadgeView: View {
    let state: ConnectivityState
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.primary)

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(indicatorColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(indicatorColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var indicatorColor: Color {
        switch state {
        case .connected:
            return .green
        case .offline:
            return .red
        }
    }

    private var title: String {
        switch state {
        case .connected:
            return "Connected"
        case let .offline(description):
            if let description, !description.isEmpty {
                return "Offline"
            }
            return "Offline"
        }
    }
}
