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
    private let keychain: KeychainStoring
    private let targetKey = "sprinkler.target_address"
    private let keychainTargetKey = "sprinkler.target_address_secure"
    private let lastSuccessKey = "sprinkler.last_success"
    private let versionKey = "sprinkler.server_version"

    init(userDefaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStorage()) {
        self.defaults = userDefaults
        self.keychain = keychain

        let keychainValue = keychain.string(forKey: keychainTargetKey)
        let defaultsValue = userDefaults.string(forKey: targetKey)

        if keychainValue == nil, let defaultsValue {
            try? keychain.set(defaultsValue, forKey: keychainTargetKey)
            userDefaults.removeObject(forKey: targetKey)
        }

        let savedAddress = keychainValue ?? defaultsValue ?? ""
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
        persistTargetAddress(targetAddress)
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

    private func persistTargetAddress(_ address: String) {
        do {
            try keychain.set(address, forKey: keychainTargetKey)
            defaults.removeObject(forKey: targetKey)
        } catch {
            defaults.set(address, forKey: targetKey)
        }
    }
}
