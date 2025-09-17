import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case requestFailed(Int)
    case decodingFailed
    case unreachable
    case invalidResponse
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided."
        case .requestFailed(let status):
            return "Request failed with status code \(status)."
        case .decodingFailed:
            return "Failed to decode the server response."
        case .unreachable:
            return "Unable to reach the sprinkler controller."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .validationFailed(let message):
            return message
        }
    }
}
