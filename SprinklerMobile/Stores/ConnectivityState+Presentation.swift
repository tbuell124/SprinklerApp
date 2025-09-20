#if canImport(SwiftUI)
import SwiftUI

/// User interface helpers that translate connectivity state into human readable
/// copy and iconography. Keeping the values alongside the enum guarantees they
/// are compiled into every platform target, preventing "no member" build
/// errors when the Settings view references them.
extension ConnectivityState {
    /// Primary text describing the current connectivity state.
    var statusTitle: String {
        switch self {
        case .connected:
            return "Connected"
        case .offline:
            return "Offline"
        }
    }

    /// Optional supporting text that surfaces troubleshooting information.
    var statusMessage: String? {
        switch self {
        case .connected:
            return "The controller is reachable on your network."
        case .offline:
            return errorDescription ?? "Tap Run Health Check to troubleshoot the connection."
        }
    }

    /// SF Symbol name used to visually represent the connectivity state.
    var statusIcon: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .offline:
            return "xmark.circle.fill"
        }
    }

    /// Accent color that matches the status symbol and hero card chip.
    var statusColor: Color {
        switch self {
        case .connected:
            return .appSuccess
        case .offline:
            return .appDanger
        }
    }
}
#endif
