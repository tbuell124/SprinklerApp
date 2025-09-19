import SwiftUI

extension ConnectivityState {
    /// SF Symbol appropriate for the state.
    var statusIcon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .offline:   return "xmark.circle.fill"
        }
    }

    /// Short, user-facing title.
    var statusTitle: String {
        switch self {
        case .connected: return "Connected"
        case .offline:   return "Offline"
        }
    }

    /// Optional detail (surfaces the error if present).
    var statusMessage: String? {
        switch self {
        case .connected: return nil
        case .offline(let message): return message
        }
    }

    /// Accent color for icons/text.
    var statusColor: Color {
        switch self {
        case .connected:
            return .appSuccess
        case .offline:
            return .appDanger
        }
    }
}
