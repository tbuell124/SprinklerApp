import Foundation

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
