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

protocol ConnectivityChecking {
    func check(baseURL: URL) async -> ConnectivityState
}

@MainActor
final class ConnectivityStore: ObservableObject {
    @Published var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Self.udKey) }
    }
    @Published var state: ConnectivityState = .offline(errorDescription: nil)
    @Published var isChecking: Bool = false

    private let checker: ConnectivityChecking
    private let defaults: UserDefaults
    static let defaultBase = "http://sprinkler.local:8000"
    private static let udKey = "sprinkler.baseURL"

    init(checker: ConnectivityChecking = HealthChecker(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.udKey)
        if let saved, !saved.isEmpty {
            self.baseURLString = saved
        } else {
            self.baseURLString = Self.defaultBase
            defaults.set(Self.defaultBase, forKey: Self.udKey)
        }
        self.checker = checker
    }

    func refresh() async { await testConnection() }

    func testConnection() async {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ConnectivityStore.normalizedBaseURL(from: trimmed) else {
            state = .offline(errorDescription: "Invalid URL")
            return
        }
        isChecking = true
        defer { isChecking = false }
        let result = await checker.check(baseURL: url)
        await MainActor.run { self.state = result }
    }

    static func normalizedBaseURL(from s: String) -> URL? {
        var str = s
        if !str.lowercased().hasPrefix("http://") && !str.lowercased().hasPrefix("https://") {
            str = "http://" + str
        }
        return URL(string: str)
    }
}

enum ConnectivityState: Equatable {
    case connected
    case offline(errorDescription: String?)
}
