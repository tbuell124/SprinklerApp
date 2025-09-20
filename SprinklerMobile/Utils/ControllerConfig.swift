import Foundation

/// Centralizes constants that describe the default sprinkler controller configuration.
///
/// Having a dedicated type keeps the default address in sync across the connectivity
/// store, placeholder UI strings, and any other code that needs to know the
/// controller's canonical base URL.
enum ControllerConfig {
    /// Default scheme used when the user does not explicitly enter one.
    static let defaultScheme = "http"

    /// Default Bonjour host name advertised by the sprinkler controller.
    static let defaultHost = "sprinkler.local"

    /// Default TCP port exposed by the controller web service.
    static let defaultPort = 8000

    /// Feature toggle that determines whether Bonjour discovery is surfaced in the UI.
    ///
    /// Keeping the switch centralised makes it easy to disable discovery in builds where
    /// Bonjour APIs are not available (for example, unit tests running on Linux).
    static let isDiscoveryEnabled = true

    /// Canonical base URL used for new installations before the user customises the address.
    static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = defaultScheme
        components.host = defaultHost
        components.port = defaultPort
        components.path = ""
        // The above configuration is guaranteed to produce a valid URL because
        // we provide the required pieces (scheme + host). Force unwrap keeps the
        // call sites tidy while still crashing in development if something ever
        // becomes inconsistent in the future.
        return components.url!
    }

    /// String representation of the canonical base URL used by default in the UI.
    static var defaultBaseAddress: String { defaultBaseURL.absoluteString }
}
