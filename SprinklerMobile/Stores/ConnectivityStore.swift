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
        didSet { defaults.set(baseURLString, forKey: Self.udKey) }
    }
    /// Published connectivity state that informs the UI whether we can reach the controller.
    @Published var state: ConnectivityState = .offline(errorDescription: nil)
    /// Indicates when a connectivity check is currently running to avoid duplicate requests.
    @Published var isChecking: Bool = false

    private let checker: ConnectivityChecking
    private let defaults: UserDefaults
    static let defaultBase = "http://sprinkler.local:8000"
    private static let udKey = "sprinkler.baseURL"

    init(checker: ConnectivityChecking = HealthChecker(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.udKey)
        self.baseURLString = (saved?.isEmpty == false) ? saved! : Self.defaultBase
        self.checker = checker
    }

    /// Convenience entry point for the UI to trigger a fresh connectivity check.
    func refresh() async { await testConnection() }

    /// Calls the health checker against the normalized base URL and updates published state.
    func testConnection() async {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ConnectivityStore.normalizedBaseURL(from: trimmed) else {
            self.state = .offline(errorDescription: "Invalid URL")
            return
        }
        isChecking = true
        defer { isChecking = false }
        let result = await checker.check(baseURL: url)
        await MainActor.run { self.state = result }
    }

    /// Normalizes text entered by the user by prepending `http://` when missing.
    static func normalizedBaseURL(from s: String) -> URL? {
        // Trim whitespace so inputs like " sprinkler.local " don't end up persisted with spaces.
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }

        // Ensure a scheme exists by defaulting to HTTP when none is provided.
        if !str.lowercased().hasPrefix("http://") && !str.lowercased().hasPrefix("https://") {
            str = "http://" + str
        }

        // Validate the URL using URLComponents to ensure we actually have a host.
        guard
            let url = URL(string: str),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host, !host.isEmpty
        else {
            return nil
        }

        // Remove any accidental fragments but otherwise preserve user-supplied path/port.
        components.fragment = nil
        return components.url
    }
}

/// Lightweight enum describing whether the sprinkler controller is reachable.
enum ConnectivityState: Equatable {
    case connected
    case offline(errorDescription: String?)
}
