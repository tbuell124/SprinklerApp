import Foundation

enum Validators {
    static func normalizeBaseAddress(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validationFailed("Please enter the sprinkler controller address.")
        }

        guard var components = URLComponents(string: trimmed) else {
            throw APIError.validationFailed("The address could not be parsed.")
        }

        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw APIError.validationFailed("The address must start with http:// or https://.")
        }

        guard components.host != nil else {
            throw APIError.validationFailed("Please include the host or IP address.")
        }

        if components.path.isEmpty {
            components.path = ""
        }

        guard let url = components.url else {
            throw APIError.validationFailed("The address is not valid.")
        }

        return url
    }
}
