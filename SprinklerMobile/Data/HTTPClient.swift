import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Describes a single HTTP call against the sprinkler controller API.
///
/// The endpoint keeps the request metadata and payload in one place so the
/// `HTTPClient` can focus on delivery/retry behaviour and callers can express
/// their intent declaratively.
struct Endpoint<Response: Decodable> {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]
    let body: AnyEncodable?
    let fallbackToEmptyBody: Bool
    let cachePolicy: URLRequest.CachePolicy?

    init(path: String,
         method: HTTPMethod = .get,
         headers: [String: String] = [:],
         body: AnyEncodable? = nil,
         fallbackToEmptyBody: Bool = false,
         cachePolicy: URLRequest.CachePolicy? = nil) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
        self.fallbackToEmptyBody = fallbackToEmptyBody
        self.cachePolicy = cachePolicy
    }
}

/// Type-erased `Encodable` wrapper so callers can hand arbitrary payloads to the networking layer
/// without forcing generics or sacrificing type safety.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        self.encodeClosure = { encoder in
            try encodable.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
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
    /// Optional dependency that supplies authorization headers for authenticated calls.
    private let authenticationProvider: AuthenticationProviding?

    /// RFC 1123 formatter used to parse `Retry-After` headers expressed as HTTP dates.
    private static let retryAfterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    /// Shared ISO8601 formatters used when decoding date strings from controller responses.
    ///
    /// Creating `ISO8601DateFormatter` instances is surprisingly expensive, so we reuse
    /// the same formatters across requests to keep date parsing fast and allocation-free.
    private static let iso8601DateFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        return [fractional, standard]
    }()

    init(sessionConfiguration: URLSessionConfiguration = .default,
         cache: URLCache = HTTPClient.makeDefaultCache(),
         maxRetries: Int = 2,
         initialRetryDelay: TimeInterval = 0.5,
         authenticationProvider: AuthenticationProviding? = nil) {
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
        self.authenticationProvider = authenticationProvider

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            for formatter in Self.iso8601DateFormatters {
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
        if let authProvider = authenticationProvider,
           let authorization = await authProvider.authorizationHeader(),
           headers[authorization.key] == nil {
            headers[authorization.key] = authorization.value
        }
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

                let statusCode = httpResponse.statusCode

                // Evaluate the HTTP status code so we can apply retry policies when needed.
                guard 200..<300 ~= statusCode else {
                    let message = extractProblemDescription(from: data)
                    let error = APIError.requestFailed(status: statusCode, message: message)

                    if attempt < maxRetries && shouldRetry(statusCode: statusCode) {
                        // Honor any server supplied `Retry-After` value and blend it with
                        // our exponential backoff using jitter to avoid client thundering herd.
                        let retryAfter = retryAfterDelayIfAvailable(from: httpResponse, statusCode: statusCode)
                        let waitTime = calculateRetryDelay(baseDelay: currentDelay, retryAfter: retryAfter)
                        attempt += 1
                        try await sleepForRetry(delay: waitTime)
                        currentDelay = nextBaseDelay(after: currentDelay, retryAfter: retryAfter)
                        continue
                    }

                    throw error
                }

                if endpoint.method == .get {
                    let cached = CachedURLResponse(response: httpResponse, data: data)
                    cache.storeCachedResponse(cached, for: request)
                }

                return try decodeResponse(data: data, responseType: Response.self)
            } catch {
                let apiError = mapToAPIError(error)
                if attempt < maxRetries && shouldRetry(apiError) {
                    // Network level failures fall back to exponential backoff with jitter.
                    let waitTime = calculateRetryDelay(baseDelay: currentDelay, retryAfter: nil)
                    attempt += 1
                    try await sleepForRetry(delay: waitTime)
                    currentDelay = nextBaseDelay(after: currentDelay, retryAfter: nil)
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
            return status == 429 || (500...599).contains(status)
        default:
            return false
        }
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        return statusCode == 429 || (500...599).contains(statusCode)
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

    /// Parse the `Retry-After` header when it is relevant so that we can respect
    /// server-side throttling instructions.
    private func retryAfterDelayIfAvailable(from response: HTTPURLResponse, statusCode: Int) -> TimeInterval? {
        guard statusCode == 429 || statusCode == 503 else { return nil }
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !header.isEmpty else { return nil }

        if let seconds = TimeInterval(header) {
            return max(0, seconds)
        }

        if let date = HTTPClient.retryAfterDateFormatter.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }

    /// Combine exponential backoff with jitter while respecting any server directive.
    private func calculateRetryDelay(baseDelay: TimeInterval, retryAfter: TimeInterval?) -> TimeInterval {
        let sanitizedBase = max(0, baseDelay)

        guard let retryAfter else {
            return Double.random(in: 0...sanitizedBase)
        }

        let sanitizedRetry = max(0, retryAfter)

        if sanitizedBase <= sanitizedRetry {
            return sanitizedRetry
        }

        let jitterRange = sanitizedBase - sanitizedRetry
        let jitter = jitterRange > 0 ? Double.random(in: 0...jitterRange) : 0
        return sanitizedRetry + jitter
    }

    /// Suspend execution for the requested retry interval while guarding against overflow.
    private func sleepForRetry(delay: TimeInterval) async throws {
        let minimumDelay = max(0, delay)
        let maximumSupportedDelay = Double(UInt64.max) / 1_000_000_000
        let cappedDelay = min(minimumDelay, maximumSupportedDelay)
        let nanoseconds = UInt64(cappedDelay * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    /// Update the base delay for the next retry attempt while keeping exponential growth.
    private func nextBaseDelay(after current: TimeInterval, retryAfter: TimeInterval?) -> TimeInterval {
        let doubled = current * 2
        if let retryAfter {
            return max(doubled, retryAfter)
        }
        return max(doubled, initialRetryDelay)
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
        let baseSegments = basePath
            .split(separator: "/")
            .filter { !$0.isEmpty }
        var endpointSegments = endpointPath
            .split(separator: "/")
            .filter { !$0.isEmpty }

        let baseCount = baseSegments.count
        if baseCount > 0, endpointSegments.count >= baseCount {
            let prefixMatches = (0..<baseCount).allSatisfy { index in
                let base = String(baseSegments[index])
                let endpoint = String(endpointSegments[index])
                return base.caseInsensitiveCompare(endpoint) == .orderedSame
            }

            if prefixMatches {
                endpointSegments.removeFirst(baseCount)
            }
        }

        let combinedSegments = baseSegments + endpointSegments
        guard !combinedSegments.isEmpty else { return "/" }
        return "/" + combinedSegments.joined(separator: "/")
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
