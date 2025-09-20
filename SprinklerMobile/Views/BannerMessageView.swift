import SwiftUI

/// Lightweight banner used to surface persistent informational and error messages above the dashboard content.
struct BannerMessageView: View {
    enum Style {
        case error
        case info
    }

    let style: Style
    let message: String
    var onDismiss: (() -> Void)?

    private var iconName: String {
        switch style {
        case .error:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var accentColor: Color {
        switch style {
        case .error:
            return .appDanger
        case .info:
            return .appAccentPrimary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.appBody)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.appSecondaryBackground.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.appShadow.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
