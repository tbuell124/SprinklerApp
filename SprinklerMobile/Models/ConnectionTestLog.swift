import Foundation

/// Describes the outcome of a connectivity test executed from the Settings screen.
struct ConnectionTestLog: Codable, Identifiable, Equatable {
    /// High level state reported by the connectivity probe.
    enum Outcome: String, Codable {
        case success
        case failure

        /// Human readable label used in the UI when rendering condensed log entries.
        var label: String {
            switch self {
            case .success:
                return "Success"
            case .failure:
                return "Failed"
            }
        }
    }

    /// Unique identifier so SwiftUI can diff log rows efficiently.
    let id: UUID
    /// Timestamp when the connectivity test finished.
    let date: Date
    /// Whether the run succeeded or failed.
    let outcome: Outcome
    /// Additional details such as latency measurements or error descriptions.
    let message: String
    /// Measured round trip duration. Optional because failures might not produce a latency.
    let latency: TimeInterval?

    init(id: UUID = UUID(),
         date: Date = Date(),
         outcome: Outcome,
         message: String,
         latency: TimeInterval?) {
        self.id = id
        self.date = date
        self.outcome = outcome
        self.message = message
        self.latency = latency
    }
}

extension ConnectionTestLog {
    /// Formats the measured latency in milliseconds for quick glance diagnostics.
    var formattedLatency: String? {
        guard let latency else { return nil }
        let milliseconds = latency * 1_000
        return String(format: "%.0f ms", milliseconds)
    }
}
