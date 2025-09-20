import Foundation
#if canImport(SwiftUI)
import SwiftUI
#else
/// Minimal stand-ins so the package compiles on platforms without SwiftUI (e.g., Linux CI).
@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    var projectedValue: Published<Value> { self }
}

protocol ObservableObject {}
#endif

/// Stores connectivity information and state for communicating with the sprinkler controller.
@MainActor
final class ConnectivityStore: ObservableObject {
    /// Base URL string entered by the user. Persisted to user defaults whenever it changes.
    @Published var baseURLString: String {
        didSet {
            defaults.set(baseURLString, forKey: Self.udKey)
            validateBaseURL()
        }
    }
    /// Published connectivity state that informs the UI whether we can reach the controller.
    @Published var state: ConnectivityState = .offline(errorDescription: nil)
    /// Indicates when a connectivity check is currently running to avoid duplicate requests.
    @Published var isChecking: Bool = false
    /// Tracks when a connectivity check last completed so the UI can surface recency information.
    @Published var lastCheckedDate: Date?
    /// Latest connectivity test captured for quick reference in the UI.
    @Published private(set) var lastTestResult: ConnectionTestLog?
    /// Rolling log of connection attempts that the settings screen can render.
    @Published private(set) var recentLogs: [ConnectionTestLog]
    /// Inline validation error surfaced underneath the controller address field.
    @Published var validationMessage: String?

    private let checker: ConnectivityChecking
    private let defaults: UserDefaults
    static let defaultBase = ControllerConfig.defaultBaseAddress
    private static let udKey = "sprinkler.baseURL"
    private let logsKey = "sprinkler.connection_logs"
    private let maxStoredLogs = 20

    init(checker: ConnectivityChecking = HealthService(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.udKey)
        self.baseURLString = (saved?.isEmpty == false) ? saved! : Self.defaultBase
        self.checker = checker
        self.recentLogs = ConnectivityStore.loadLogs(from: defaults, key: logsKey)
        self.lastTestResult = recentLogs.first
    }

    /// Convenience entry point for the UI to trigger a fresh connectivity check.
    func refresh() async { await testConnection() }

    /// Calls the health checker against the normalized base URL and updates published state.
    func testConnection() async {
        guard !isChecking else { return }

        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Enter the controller address."
            state = .offline(errorDescription: "Address missing")
            return
        }

        let normalizedURL: URL
        do {
            normalizedURL = try Validators.normalizeBaseAddress(trimmed)
            if normalizedURL.absoluteString != baseURLString {
                baseURLString = normalizedURL.absoluteString
            }
            validationMessage = nil
        } catch let error as APIError {
            validationMessage = error.localizedDescription
            state = .offline(errorDescription: error.localizedDescription)
            return
        } catch {
            validationMessage = "The address is not valid."
            state = .offline(errorDescription: "Invalid address")
            return
        }

        let start = Date()
        isChecking = true
        defer { isChecking = false }
        let result = await checker.check(baseURL: normalizedURL)
        let completedAt = Date()
        lastCheckedDate = completedAt
        self.state = result

        let latency = completedAt.timeIntervalSince(start)
        let message: String
        let outcome: ConnectionTestLog.Outcome

        switch result {
        case .connected:
            outcome = .success
            message = "Controller responded in \(Self.formatLatency(latency))"
        case let .offline(errorDescription):
            outcome = .failure
            message = errorDescription ?? "Controller is unreachable"
        }

        let log = ConnectionTestLog(outcome: outcome,
                                    message: message,
                                    latency: latency)
        lastTestResult = log
        appendLog(log)
    }

    /// Normalizes text entered by the user by prepending `http://` when missing.
    static func normalizedBaseURL(from s: String) -> URL? {
        return try? Validators.normalizeBaseAddress(s)
    }
}

private extension ConnectivityStore {
    /// Validates the currently entered controller address and produces immediate feedback.
    func validateBaseURL() {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Enter the controller address."
            return
        }

        do {
            _ = try Validators.normalizeBaseAddress(trimmed)
            validationMessage = nil
        } catch let error as APIError {
            validationMessage = error.localizedDescription
        } catch {
            validationMessage = "The address is not valid."
        }
    }

    /// Persists a connectivity log entry and keeps the in-memory array capped.
    func appendLog(_ log: ConnectionTestLog) {
        var updated = recentLogs
        updated.insert(log, at: 0)
        if updated.count > maxStoredLogs {
            updated = Array(updated.prefix(maxStoredLogs))
        }
        recentLogs = updated
        ConnectivityStore.persistLogs(updated, defaults: defaults, key: logsKey)
    }

    /// Loads stored connectivity logs from user defaults.
    static func loadLogs(from defaults: UserDefaults, key: String) -> [ConnectionTestLog] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let logs = try? decoder.decode([ConnectionTestLog].self, from: data) {
            return logs
        }
        return []
    }

    /// Serialises log entries back to user defaults so diagnostics persist across launches.
    static func persistLogs(_ logs: [ConnectionTestLog], defaults: UserDefaults, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(logs) {
            defaults.set(data, forKey: key)
        }
    }

    /// Human friendly latency formatter shared across UI and logging layers.
    static func formatLatency(_ latency: TimeInterval) -> String {
        let milliseconds = latency * 1_000
        if milliseconds >= 1_000 {
            return String(format: "%.2f s", latency)
        }
        return String(format: "%.0f ms", milliseconds)
    }
}

/// Lightweight enum describing whether the sprinkler controller is reachable.
enum ConnectivityState: Equatable {
    case connected
    case offline(errorDescription: String?)
}

#if canImport(SwiftUI)

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
        case let .offline(description):
            return description ?? "Tap Run Health Check to troubleshoot the connection."
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
