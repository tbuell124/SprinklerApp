import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction used to verify sprinkler controller connectivity.
protocol ConnectivityChecking {
    /// Executes a connectivity check against the provided base URL.
    func check(baseURL: URL) async -> ConnectivityState
}

/// Performs a controller health check, supporting both `/status` and `/api/status` endpoints while
/// automatically attaching the stored authentication token when available.
struct HealthService: ConnectivityChecking {
    private let session: URLSession
    private let authentication: AuthenticationProviding?

    /// Creates a health service backed by the supplied URL session.
    /// - Parameters:
    ///   - session: URLSession used to issue network requests. Defaults to `.shared` for convenience.
    ///   - authentication: Optional provider that supplies the authorization header required by secured controllers.
    init(session: URLSession = .shared, authentication: AuthenticationProviding? = nil) {
        self.session = session
        self.authentication = authentication
    }

    func check(baseURL: URL) async -> ConnectivityState {
        let normalizedBase = URLNormalize.normalized(baseURL)
        let header = await authentication?.authorizationHeader()
        var lastError: String?

        for statusURL in Self.candidateStatusURLs(for: normalizedBase) {
            do {
                var request = Self.makeStatusRequest(url: statusURL)
                if let header { request.addValue(header.value, forHTTPHeaderField: header.key) }

                let (data, response) = try await session.data(for: request, delegate: nil)

                guard let http = response as? HTTPURLResponse else {
                    lastError = "Invalid response"
                    continue
                }

                if http.statusCode == 204 {
                    return .connected
                }

                guard (200..<300).contains(http.statusCode) else {
                    lastError = "HTTP \(http.statusCode)"
                    continue
                }

                switch Self.interpretStatusPayload(data) {
                case .some(true):
                    return .connected
                case .some(false):
                    return .offline(errorDescription: "Controller reported unhealthy status")
                case .none:
                    lastError = "Unrecognized status payload"
                    continue
                }
            } catch let urlError as URLError {
                lastError = Self.describe(urlError)
            } catch {
                lastError = error.localizedDescription
            }
        }

        return .offline(errorDescription: lastError ?? "Unable to reach controller")
    }

    /// Builds a request configured for a lightweight JSON status check.
    private static func makeStatusRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 8
        )
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Generates candidate status endpoints, gracefully handling different controller URL schemes.
    private static func candidateStatusURLs(for baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var visited = Set<String>()
        let normalizedBase = URLNormalize.normalized(baseURL)
        let segments = pathSegments(in: normalizedBase)

        func append(_ url: URL) {
            let normalized = URLNormalize.normalized(url)
            let key = normalized.absoluteString
            if visited.insert(key).inserted {
                urls.append(normalized)
            }
        }

        if let preferred = preferredAPIStatusURL(for: normalizedBase, segments: segments) {
            append(preferred)
        }

        if let last = segments.last, last.caseInsensitiveCompare("status") == .orderedSame {
            append(normalizedBase)
        } else {
            append(normalizedBase.appendingPathComponent("status"))
        }

        if segments.contains(where: { $0.caseInsensitiveCompare("api") == .orderedSame }),
           let root = removingPathSegments(startingWith: "api", from: normalizedBase) {
            append(root.appendingPathComponent("status"))
        }

        return urls
    }

    /// Extracts normalized, non-empty path segments for a URL.
    private static func pathSegments(in url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    }

    /// Removes the specified segment and everything after it from the URL's path.
    private static func removingPathSegments(startingWith segment: String, from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var segments = pathSegments(in: url)
        guard let index = segments.firstIndex(where: { $0.caseInsensitiveCompare(segment) == .orderedSame }) else {
            return nil
        }
        segments.removeSubrange(index...)
        if segments.isEmpty {
            components.percentEncodedPath = ""
        } else {
            components.percentEncodedPath = "/" + segments.joined(separator: "/")
        }
        return components.url.map(URLNormalize.normalized)
    }

    /// Determines the most appropriate `/api/status` endpoint for the supplied base URL, if any.
    private static func preferredAPIStatusURL(for baseURL: URL, segments: [String]) -> URL? {
        guard !segments.isEmpty else {
            return baseURL.appendingPathComponent("api").appendingPathComponent("status")
        }

        if segments.count >= 2,
           segments[segments.count - 2].caseInsensitiveCompare("api") == .orderedSame,
           segments.last?.caseInsensitiveCompare("status") == .orderedSame {
            return baseURL
        }

        if let last = segments.last,
           last.caseInsensitiveCompare("api") == .orderedSame {
            return baseURL.appendingPathComponent("status")
        }

        if segments.contains(where: { $0.caseInsensitiveCompare("api") == .orderedSame }) {
            return nil
        }

        return baseURL.appendingPathComponent("api").appendingPathComponent("status")
    }

    /// Attempts to interpret a JSON status payload and determine whether the controller is healthy.
    private static func interpretStatusPayload(_ data: Data) -> Bool? {
        guard !data.isEmpty else { return true }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        if let ok = dictionary["ok"] as? Bool {
            return ok
        }

        if let healthy = dictionary["healthy"] as? Bool {
            return healthy
        }

        if let status = dictionary["status"] as? String {
            let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["ok", "online", "ready", "healthy"].contains(normalized) {
                return true
            }
            if ["offline", "error", "fault", "failed"].contains(normalized) {
                return false
            }
        }

        return nil
    }

    /// Generates a human readable error string for common URL loading failures.
    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "Connection timed out"
        case .cannotFindHost, .dnsLookupFailed:
            return "Host could not be resolved"
        case .notConnectedToInternet:
            return "No internet connection"
        case .cannotConnectToHost:
            return "Unable to open a connection to the controller"
        default:
            return error.localizedDescription
        }
    }
}
