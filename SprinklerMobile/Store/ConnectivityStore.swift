import Foundation

#if canImport(Combine)
import Combine
#else
@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public var projectedValue: Published<Value> { self }
}

public protocol ObservableObject {}
#endif

/// `ConnectivityStore` owns the user-facing connectivity state and persists the selected base URL.
/// It bridges the SwiftUI views with the `HealthChecker` service using async/await.
@MainActor
public final class ConnectivityStore: ObservableObject {
    private enum Constants {
        static let defaultsKey = "sprinkler.baseURL"
        static let defaultBaseURLString = "http://sprinkler.local:8000"
    }

    /// URL string bound to the Settings screen text field.
    @Published public var baseURLString: String

    /// Latest connectivity result displayed throughout the UI.
    @Published public var state: ConnectivityState

    /// Exposes whether the store is currently running a health check.
    @Published public private(set) var isChecking: Bool = false

    private let defaults: UserDefaults
    private let healthChecker: HealthChecking

    public init(userDefaults: UserDefaults = .standard,
                healthChecker: HealthChecking = HealthChecker()) {
        self.defaults = userDefaults
        self.healthChecker = healthChecker

        let persistedURL = userDefaults.string(forKey: Constants.defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let persistedURL, !persistedURL.isEmpty {
            self.baseURLString = persistedURL
        } else {
            self.baseURLString = Constants.defaultBaseURLString
            userDefaults.register(defaults: [Constants.defaultsKey: Constants.defaultBaseURLString])
        }

        self.state = .offline(errorDescription: "Not checked yet.")
    }

    /// Runs the health check when the user taps "Test Connection" in Settings.
    public func testConnection() async {
        await performHealthCheck()
    }

    /// Invoked from pull-to-refresh in the dashboard to re-run the health check.
    public func refresh() async {
        await performHealthCheck()
    }

    private func performHealthCheck() async {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedURL = normalize(baseURL: trimmed) else {
            state = .offline(errorDescription: "Enter a valid base URL, for example http://sprinkler.local:8000.")
            return
        }

        baseURLString = normalizedURL.absoluteString
        defaults.set(baseURLString, forKey: Constants.defaultsKey)

        isChecking = true
        defer { isChecking = false }

        let result = await healthChecker.check(baseURL: normalizedURL)
        state = result
    }

    private func normalize(baseURL: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }

        var workingURL = baseURL
        if !workingURL.contains("://") {
            workingURL = "http://" + workingURL
        }

        guard var components = URLComponents(string: workingURL) else { return nil }
        if components.scheme == nil {
            components.scheme = "http"
        }

        // Ensure we have at least a host component.
        guard components.host != nil else { return nil }

        // Drop trailing path slashes for consistency.
        if var path = components.path.nonEmpty {
            while path.hasSuffix("/") { path.removeLast() }
            components.path = path
        }

        return components.url
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
