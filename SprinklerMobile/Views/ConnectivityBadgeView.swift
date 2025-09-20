import SwiftUI

struct ConnectivityBadgeView: View {
    let state: ConnectivityState
    var isLoading: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appButton)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .accessibilityLabel("Checking connectivity")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appSecondaryBackground.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(indicatorColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.appShadow.opacity(0.1), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var indicatorColor: Color { state.statusColor }

    private var title: String { state.statusTitle }

    private var subtitle: String? { state.statusMessage }

    private var accessibilitySummary: String {
        if let subtitle {
            return "Controller status: \(title). \(subtitle)"
        }
        return "Controller status: \(title)"
    }
}
