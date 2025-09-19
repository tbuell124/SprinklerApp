import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstraction used to verify sprinkler controller connectivity.
protocol ConnectivityChecking {
    /// Executes a connectivity check against the provided base URL.
    func check(baseURL: URL) async -> ConnectivityState
}

/// Performs a controller health check, supporting both `/status` and `/api/status` endpoints.
struct HealthChecker: ConnectivityChecking {
    private let session: URLSession

    /// Creates a health checker backed by the supplied URL session.
    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(baseURL: URL) async -> ConnectivityState {
        var lastError: String?

        for statusURL in Self.candidateStatusURLs(for: baseURL) {
            do {
                let request = Self.makeStatusRequest(url: statusURL)
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    lastError = "Invalid response"
                    continue
                }

                // A controller may respond with 204 (No Content) when everything is OK.
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
        let segments = pathSegments(in: baseURL)

        if let last = segments.last, last.caseInsensitiveCompare("status") == .orderedSame {
            urls.append(baseURL)
        } else {
            urls.append(baseURL.appendingPathComponent("status"))

            if !segments.contains(where: { $0.caseInsensitiveCompare("api") == .orderedSame }) {
                let apiURL = baseURL
                    .appendingPathComponent("api")
                    .appendingPathComponent("status")
                if !urls.contains(apiURL) {
                    urls.append(apiURL)
                }
            }
        }

        return urls
    }

    /// Extracts normalized, non-empty path segments for a URL.
    private static func pathSegments(in url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
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
