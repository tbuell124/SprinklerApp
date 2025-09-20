import Foundation

/// Collection of helpers that normalise user-supplied or discovered controller URLs.
///
/// These utilities strip Bonjour artefacts such as trailing dots, ensure hosts are
/// consistently lowercased, and return canonical URLs that can be safely persisted
/// or displayed to the user.
enum URLNormalize {
    /// Removes whitespace, trailing dots and uppercasing from the supplied host name.
    /// - Parameter host: Raw host string extracted from user input or Bonjour discovery.
    /// - Returns: A cleaned up host value suitable for use in URLComponents.
    static func sanitizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        var sanitized = trimmed
        while sanitized.last == "." {
            sanitized.removeLast()
        }

        return sanitized.lowercased()
    }

    /// Produces a canonical URL by cleaning up the host and removing redundant trailing slashes.
    /// - Parameter url: The original URL.
    /// - Returns: A URL with a sanitized host and no single trailing slash path.
    static func normalized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if let host = components.host, !host.isEmpty {
            let cleaned = sanitizedHost(host)
            if !cleaned.isEmpty {
                components.host = cleaned
            }
        }

        if components.percentEncodedPath == "/" {
            components.percentEncodedPath = ""
        }

        return components.url ?? url
    }
}
