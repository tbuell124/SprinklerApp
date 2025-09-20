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

    private var indicatorColor: Color {
        switch state {
        case .connected:
            return .appSuccess
        case .offline:
            return .appDanger
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

    private var subtitle: String? {
        switch state {
        case .connected:
            return "The controller is reachable on your network."
        case let .offline(description):
            return description ?? "Tap Run Health Check to troubleshoot the connection."
        }
    }

    private var accessibilitySummary: String {
        if let subtitle {
            return "Controller status: \(title). \(subtitle)"
        }
        return "Controller status: \(title)"
    }
}
