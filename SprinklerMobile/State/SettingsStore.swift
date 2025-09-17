import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var targetAddress: String
    @Published var validationError: String?
    @Published private(set) var resolvedBaseURL: URL?
    @Published var isTestingConnection: Bool = false
    @Published var lastSuccessfulConnection: Date?
    @Published var lastFailure: APIError?
    @Published var serverVersion: String?

    private let defaults: UserDefaults
    private let targetKey = "sprinkler.target_address"
    private let lastSuccessKey = "sprinkler.last_success"
    private let versionKey = "sprinkler.server_version"

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        let savedAddress = userDefaults.string(forKey: targetKey) ?? ""
        self.targetAddress = savedAddress
        if let url = try? Validators.normalizeBaseAddress(savedAddress) {
            self.resolvedBaseURL = url
        }
        self.lastSuccessfulConnection = userDefaults.object(forKey: lastSuccessKey) as? Date
        self.serverVersion = userDefaults.string(forKey: versionKey)
    }

    func resolveCurrentAddress() throws -> URL {
        let url = try Validators.normalizeBaseAddress(targetAddress)
        validationError = nil
        resolvedBaseURL = url
        defaults.set(targetAddress, forKey: targetKey)
        return url
    }

    func setValidationError(_ error: APIError) {
        if case let .validationFailed(message) = error {
            validationError = message
        } else {
            validationError = error.localizedDescription
        }
    }

    func recordConnectionSuccess(version: String?) {
        lastSuccessfulConnection = Date()
        lastFailure = nil
        defaults.set(lastSuccessfulConnection, forKey: lastSuccessKey)
        if let version {
            serverVersion = version
            defaults.set(version, forKey: versionKey)
        }
    }

    func recordConnectionFailure(_ error: APIError) {
        lastFailure = error
    }
}
