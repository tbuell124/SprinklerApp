import SwiftUI

/// Presentation helpers that translate connectivity state into user-friendly strings and imagery.
extension ConnectivityState {
    /// Machine readable title for the active connectivity state.
    var statusTitle: String {
        switch self {
        case .connected:
            return "Connected"
        case .offline:
            return "Offline"
        }
    }

    /// A short message explaining the status in more detail for the hero card and highlight section.
    var statusMessage: String {
        switch self {
        case .connected:
            return "The controller is reachable on your network."
        case let .offline(description):
            return description ?? "Tap Run Health Check to troubleshoot the connection."
        }
    }

    /// Symbol representing the current state.
    var statusIcon: String {
        switch self {
        case .connected:
            return "checkmark.seal"
        case .offline:
            return "exclamationmark.triangle"
        }
    }

    /// Tint color that keeps the state consistent across the dashboard.
    var statusColor: Color {
        switch self {
        case .connected:
            return .green
        case .offline:
            return .orange
        }
    }
}
