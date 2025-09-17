import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

/// Thin wrapper around `URLSession` that adds request retries, offline caching and
/// better error diagnostics tailored to the sprinkler controller.
final class HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cache: URLCache
    private let maxRetries: Int
    private let initialRetryDelay: TimeInterval

    init(sessionConfiguration: URLSessionConfiguration = .default,
         cache: URLCache = HTTPClient.makeDefaultCache(),
         maxRetries: Int = 2,
         initialRetryDelay: TimeInterval = 0.5) {
        let configuration = sessionConfiguration
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy

        // Use a standard `URLSession` without TLS pinning because the controller
        // communicates exclusively with the Pi over the local network via HTTP.
        // This avoids confusion about certificate requirements while keeping
        // the configuration focused on low-latency LAN communication.
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.cache = cache
        self.maxRetries = maxRetries
        self.initialRetryDelay = initialRetryDelay

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatters: [ISO8601DateFormatter] = {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let standard = ISO8601DateFormatter()
                standard.formatOptions = [.withInternetDateTime]
                return [fractional, standard]
            }()

            for formatter in formatters {
                if let date = formatter.date(from: value) {
                    return date
                }
            }

            if let interval = TimeInterval(value) {
                return Date(timeIntervalSince1970: interval)
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date format: \(value)")
        }

        encoder.outputFormatting = [.prettyPrinted]
    }

    func request<Response: Decodable>(_ endpoint: Endpoint<Response>, baseURL: URL) async throws -> Response {
        let bodyData = try endpoint.body.map { try encoder.encode($0) }

        do {
            return try await send(endpoint: endpoint, baseURL: baseURL, bodyData: bodyData)
        } catch let error as APIError {
            if endpoint.fallbackToEmptyBody,
               case let .requestFailed(status, _) = error,
               (status == 400 || status == 415) {
                return try await send(endpoint: endpoint, baseURL: baseURL, bodyData: nil)
            }
            throw error
        }
    }

    private func send<Response: Decodable>(endpoint: Endpoint<Response>,
                                           baseURL: URL,
                                           bodyData: Data?) async throws -> Response {
        let requestURL = try makeURL(baseURL: baseURL, endpointPath: endpoint.path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = bodyData
        request.cachePolicy = endpoint.cachePolicy ?? (endpoint.method == .get ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData)

        var headers = endpoint.headers
        if bodyData != nil {
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
        }
        headers["Accept"] = headers["Accept"] ?? "application/json"
        request.allHTTPHeaderFields = headers

        var attempt = 0
        var currentDelay = initialRetryDelay

        while attempt <= maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                if httpResponse.statusCode == 304,
                   endpoint.method == .get,
                   let cachedResponse = cache.cachedResponse(for: request) {
                    return try decodeResponse(data: cachedResponse.data, responseType: Response.self)
                }

                guard 200..<300 ~= httpResponse.statusCode else {
                    let message = extractProblemDescription(from: data)
                    throw APIError.requestFailed(status: httpResponse.statusCode, message: message)
                }

                if endpoint.method == .get {
                    let cached = CachedURLResponse(response: httpResponse, data: data)
                    cache.storeCachedResponse(cached, for: request)
                }

                return try decodeResponse(data: data, responseType: Response.self)
            } catch {
                let apiError = mapToAPIError(error)
                if attempt < maxRetries && shouldRetry(apiError) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= 2
                    continue
                }

                if endpoint.method == .get,
                   let cachedResponse = cache.cachedResponse(for: request),
                   let httpResponse = cachedResponse.response as? HTTPURLResponse,
                   200..<300 ~= httpResponse.statusCode {
                    if let decoded = try? decodeResponse(data: cachedResponse.data, responseType: Response.self) {
                        return decoded
                    }
                }

                throw apiError
            }
        }

        throw APIError.invalidResponse
    }

    private func decodeResponse<Response: Decodable>(data: Data, responseType: Response.Type) throws -> Response {
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if data.isEmpty || trimmed.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    private func shouldRetry(_ error: APIError) -> Bool {
        switch error {
        case .unreachable:
            return true
        case .requestFailed(let status, _):
            return (500...599).contains(status)
        default:
            return false
        }
    }

    private func mapToAPIError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .secureConnectionFailed:
                return .unreachable
            default:
                return .invalidResponse
            }
        }

        let nsError = error as NSError
        if nsError.code == NSURLErrorTimedOut ||
            nsError.code == NSURLErrorCannotFindHost ||
            nsError.code == NSURLErrorCannotConnectToHost {
            return .unreachable
        }

        return .invalidResponse
    }

    private func extractProblemDescription(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let problem = try? decoder.decode(ProblemDetails.self, from: data),
           let message = problem.displayMessage {
            return message
        }

        if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }

        return nil
    }

    private func makeURL(baseURL: URL, endpointPath: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.percentEncodedPath = joinedPath(basePath: components.percentEncodedPath, endpointPath: endpointPath)
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func joinedPath(basePath: String, endpointPath: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedEndpoint = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = [trimmedBase, trimmedEndpoint].filter { !$0.isEmpty }
        guard !segments.isEmpty else { return "/" }
        return "/" + segments.joined(separator: "/")
    }

    private static func makeDefaultCache() -> URLCache {
        URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
    }
}

private struct ProblemDetails: Decodable {
    let message: String?
    let detail: String?
    let error: String?
    let description: String?

    var displayMessage: String? {
        message ?? detail ?? error ?? description
    }
}
