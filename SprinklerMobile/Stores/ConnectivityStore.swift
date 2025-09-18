import Foundation
#if canImport(SwiftUI)
import SwiftUI
#else
@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    var projectedValue: Published<Value> { self }
}

protocol ObservableObject {}
#endif

/// Stores the connectivity settings and state for communicating with the sprinkler controller.
@MainActor
final class ConnectivityStore: ObservableObject {
    /// Base URL string for the sprinkler controller API. Persists to user defaults on change.
    @Published var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Self.udKey) }
    }
    /// Current connectivity state for the controller.
    @Published var state: ConnectivityState = .offline(errorDescription: nil)
    /// Whether a connectivity check is currently in progress.
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

    /// Public entry point for refreshing connectivity state.
    func refresh() async { await testConnection() }

    /// Tests connectivity to the configured base URL, updating the published state accordingly.
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

    /// Normalizes a human-entered string into a usable base URL, defaulting to HTTP when missing.
    static func normalizedBaseURL(from s: String) -> URL? {
        var str = s
        if !str.lowercased().hasPrefix("http://") && !str.lowercased().hasPrefix("https://") {
            str = "http://" + str
        }
        return URL(string: str)
    }
}

/// Represents connectivity state for the sprinkler controller.
enum ConnectivityState: Equatable {
    case connected
    case offline(errorDescription: String?)
}
