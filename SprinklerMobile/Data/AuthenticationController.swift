import Foundation

/// Protocol describing a type that can vend authentication headers for outbound requests.
///
/// This lets the networking stack remain decoupled from how credentials are stored while
/// still allowing the HTTP client to attach security metadata when needed.
protocol AuthenticationProviding: AnyObject {
    /// Returns the HTTP header field/value pair that should be attached to the request.
    /// - Returns: A tuple describing the header key and value or `nil` when no credentials are available.
    func authorizationHeader() async -> (key: String, value: String)?
}

/// Extends ``AuthenticationProviding`` with mutation capabilities so the application can
/// update credentials as the user supplies new tokens.
protocol AuthenticationManaging: AuthenticationProviding {
    /// Persists the supplied token securely for future requests.
    /// - Parameter token: The raw authentication token or `nil` to remove the current credential.
    func updateToken(_ token: String?) async throws

    /// Retrieves the currently stored token so callers can reflect it in UI or analytics if needed.
    func currentToken() async -> String?
}

/// Actor responsible for securely persisting and vendoring the authorization token used by the sprinkler API.
///
/// The token is stored in the keychain so it survives application launches without being exposed in user defaults
/// or logs. The actor keeps an in-memory cache to avoid repeated keychain lookups during steady state operation.
actor AuthenticationController: AuthenticationManaging {
    private let keychain: KeychainStoring
    private let tokenKey: String
    private let headerField: String
    private let scheme: String
    private var cachedToken: String?

    /// Creates a new controller that stores credentials under the provided keychain key.
    /// - Parameters:
    ///   - keychain: Dependency that performs the actual keychain read/write operations.
    ///   - tokenKey: Key under which the token will be stored. Defaults to ``sprinkler.auth_token``.
    ///   - headerField: HTTP header field that should carry the credential. Defaults to ``Authorization``.
    ///   - scheme: Authorization scheme prepended to the raw token. Defaults to ``Bearer``.
    init(keychain: KeychainStoring = KeychainStorage(),
         tokenKey: String = "sprinkler.auth_token",
         headerField: String = "Authorization",
         scheme: String = "Bearer") {
        self.keychain = keychain
        self.tokenKey = tokenKey
        self.headerField = headerField
        self.scheme = scheme
        self.cachedToken = AuthenticationController.sanitize(keychain.string(forKey: tokenKey))
    }

    func authorizationHeader() async -> (key: String, value: String)? {
        guard let token = cachedToken else { return nil }
        return (headerField, "\(scheme) \(token)")
    }

    func updateToken(_ token: String?) async throws {
        if let sanitized = AuthenticationController.sanitize(token) {
            try keychain.set(sanitized, forKey: tokenKey)
            cachedToken = sanitized
        } else {
            keychain.deleteValue(forKey: tokenKey)
            cachedToken = nil
        }
    }

    func currentToken() async -> String? {
        cachedToken
    }

    private static func sanitize(_ token: String?) -> String? {
        guard let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
