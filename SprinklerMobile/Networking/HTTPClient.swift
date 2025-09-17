import Foundation

final class HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

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

        var combinedHeaders = headers
        if bodyData != nil {
            combinedHeaders["Content-Type"] = combinedHeaders["Content-Type"] ?? "application/json"
        }
        combinedHeaders["Accept"] = combinedHeaders["Accept"] ?? "application/json"

        request.allHTTPHeaderFields = combinedHeaders

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw APIError.requestFailed(httpResponse.statusCode)
            }

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
        } catch let error as APIError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCannotFindHost || nsError.code == NSURLErrorCannotConnectToHost {
                throw APIError.unreachable
            }
            throw APIError.invalidResponse
        }
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
