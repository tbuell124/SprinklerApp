import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

final class HTTPClient {
    private let session: URLSession
    private let sessionDelegate: URLSessionDelegate?
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

        let delegate = SSLPinningDelegate()
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.sessionDelegate = delegate

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

    func request<T: Decodable>(url: URL,
                               method: HTTPMethod = .get,
                               headers: [String: String] = [:],
                               body: Encodable? = nil,
                               fallbackToEmptyBody: Bool = false,
                               decode type: T.Type = T.self) async throws -> T {
        let initialBodyData: Data?
        if let body {
            initialBodyData = try encoder.encode(AnyEncodable(body))
        } else {
            initialBodyData = nil
        }

        do {
            return try await send(url: url,
                                  method: method,
                                  headers: headers,
                                  bodyData: initialBodyData,
                                  decode: T.self)
        } catch let error as APIError {
            if fallbackToEmptyBody,
               case let .requestFailed(code) = error,
               (code == 400 || code == 415) {
                return try await send(url: url,
                                      method: method,
                                      headers: headers,
                                      bodyData: nil,
                                      decode: T.self)
            }
            throw error
        }
    }

    private func send<T: Decodable>(url: URL,
                                    method: HTTPMethod,
                                    headers: [String: String],
                                    bodyData: Data?,
                                    decode type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = bodyData
        request.cachePolicy = method == .get ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData

        var combinedHeaders = headers
        if bodyData != nil {
            combinedHeaders["Content-Type"] = combinedHeaders["Content-Type"] ?? "application/json"
        }
        combinedHeaders["Accept"] = combinedHeaders["Accept"] ?? "application/json"

        request.allHTTPHeaderFields = combinedHeaders

        var attempt = 0
        var currentDelay = initialRetryDelay

        while attempt <= maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                if httpResponse.statusCode == 304,
                   method == .get,
                   let cachedResponse = cache.cachedResponse(for: request) {
                    return try decodeResponse(data: cachedResponse.data, responseType: T.self)
                }

                guard 200..<300 ~= httpResponse.statusCode else {
                    throw APIError.requestFailed(httpResponse.statusCode)
                }

                if method == .get {
                    let cached = CachedURLResponse(response: httpResponse, data: data)
                    cache.storeCachedResponse(cached, for: request)
                }

                return try decodeResponse(data: data, responseType: T.self)
            } catch {
                let apiError = mapToAPIError(error)
                if attempt < maxRetries && shouldRetry(apiError) {
                    attempt += 1
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= 2
                    continue
                }

                if method == .get,
                   let cachedResponse = cache.cachedResponse(for: request),
                   let httpResponse = cachedResponse.response as? HTTPURLResponse,
                   200..<300 ~= httpResponse.statusCode {
                    if let decoded = try? decodeResponse(data: cachedResponse.data, responseType: T.self) {
                        return decoded
                    }
                }

                throw apiError
            }
        }

        throw APIError.invalidResponse
    }

    private func decodeResponse<T: Decodable>(data: Data, responseType: T.Type) throws -> T {
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    private func shouldRetry(_ error: APIError) -> Bool {
        switch error {
        case .unreachable:
            return true
        case .requestFailed(let status):
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

    private static func makeDefaultCache() -> URLCache {
        URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
    }
}

private struct AnyEncodable: Encodable {
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
