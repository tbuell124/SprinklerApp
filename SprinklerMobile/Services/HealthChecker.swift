import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Represents the connectivity status of the sprinkler controller.
/// - connected: The controller responded with a valid JSON object.
/// - offline: The controller is unreachable or returned an invalid response. An optional description
///            explains the failure that occurred.
public enum ConnectivityState: Equatable {
    case connected
    case offline(errorDescription: String?)
}

/// Lightweight protocol that exposes the connectivity probing API. This enables dependency
/// injection in unit tests via a mocked implementation.
public protocol HealthChecking {
    func check(baseURL: URL) async -> ConnectivityState
}

/// Concrete implementation that performs an HTTP GET to `{baseURL}/api/status` using `URLSession`.
/// A controller is considered reachable when a 2xx response containing a top-level JSON object is
/// returned. All other responses are treated as offline, including network failures, timeouts and
/// invalid JSON payloads.
public struct HealthChecker: HealthChecking {
    private enum Constants {
        static let timeout: TimeInterval = 6.0
        static let apiComponent = "api"
        static let statusComponent = "status"
    }

    private let session: URLSession

    /// Creates a checker with an optional `URLSession`. An ephemeral configuration with a 6 second
    /// timeout is used by default to avoid caching responses and to fail fast when the controller is
    /// offline.
    public init(session: URLSession? = nil) {
        self.session = session ?? HealthChecker.makeDefaultSession()
    }

    public func check(baseURL: URL) async -> ConnectivityState {
        let statusURL = makeStatusURL(from: baseURL)
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .offline(errorDescription: "Received an invalid response from the server.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return .offline(errorDescription: "Server responded with status code \(httpResponse.statusCode).")
            }

            guard isTopLevelJSONObject(data: data) else {
                return .offline(errorDescription: "Server returned a non-JSON response.")
            }

            return .connected
        } catch {
            return .offline(errorDescription: errorDescription(for: error))
        }
    }

    private func makeStatusURL(from baseURL: URL) -> URL {
        // Ensure we respect any existing path components while always appending /api/status.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
                .appendingPathComponent(Constants.apiComponent)
                .appendingPathComponent(Constants.statusComponent)
        }

        var path = components.path
        if !path.hasSuffix("/") {
            path.append("/")
        }
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        path.append(contentsOf: Constants.apiComponent)
        path.append("/")
        path.append(contentsOf: Constants.statusComponent)
        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? baseURL
            .appendingPathComponent(Constants.apiComponent)
            .appendingPathComponent(Constants.statusComponent)
    }

    private func isTopLevelJSONObject(data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json is [String: Any]
        } catch {
            return false
        }
    }

    private func errorDescription(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Cannot find host. Check that the base URL is correct."
            case .timedOut:
                return "Connection timed out. Ensure the controller is running."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "Unable to connect to the controller."
            default:
                break
            }
            return urlError.localizedDescription
        }
        return error.localizedDescription
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.timeout
        configuration.timeoutIntervalForResource = Constants.timeout
        return URLSession(configuration: configuration)
    }
}
