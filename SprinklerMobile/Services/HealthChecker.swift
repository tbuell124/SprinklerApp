import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HealthChecker: ConnectivityChecking {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(baseURL: URL) async -> ConnectivityState {
        var statusURL = baseURL
        statusURL.append(path: "/api/status")

        var req = URLRequest(url: statusURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.httpMethod = "GET"
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .offline(errorDescription: "Bad status")
            }
            // valid JSON object = connected
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (obj != nil) ? .connected : .offline(errorDescription: "Non-JSON")
        } catch {
            return .offline(errorDescription: error.localizedDescription)
        }
    }
}
