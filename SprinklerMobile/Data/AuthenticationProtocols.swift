import Foundation

/// Protocol describing a type that can vend authentication headers for outbound requests.
///
/// This lets the networking stack remain decoupled from how credentials are stored while
/// still allowing the HTTP client to attach security metadata when needed.
public protocol AuthenticationProviding: AnyObject {
    /// Returns the HTTP header field/value pair that should be attached to the request.
    /// - Returns: A tuple describing the header key and value or `nil` when no credentials are available.
    func authorizationHeader() async -> (key: String, value: String)?
}

/// Extends ``AuthenticationProviding`` with mutation capabilities so the application can
/// update credentials as the user supplies new tokens.
public protocol AuthenticationManaging: AuthenticationProviding {
    /// Persists the supplied token securely for future requests.
    /// - Parameter token: The raw authentication token or `nil` to remove the current credential.
    func updateToken(_ token: String?) async throws

    /// Retrieves the currently stored token so callers can reflect it in UI or analytics if needed.
    func currentToken() async -> String?
}
