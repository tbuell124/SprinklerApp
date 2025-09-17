import Foundation

enum Validators {
    static func normalizeBaseAddress(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validationFailed("Please enter the sprinkler controller address.")
        }

        let components = URLComponents(string: trimmed)
        let normalizedComponents: URLComponents

        if let components, let scheme = components.scheme, !scheme.isEmpty {
            normalizedComponents = components
        } else {
            guard let fallbackComponents = URLComponents(string: "http://\(trimmed)") else {
                throw APIError.validationFailed("The address could not be parsed.")
            }
            normalizedComponents = fallbackComponents
        }

        guard let scheme = normalizedComponents.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw APIError.validationFailed("The address must start with http:// or https://.")
        }

        guard normalizedComponents.host != nil else {
            throw APIError.validationFailed("Please include the host or IP address.")
        }

        var mutableComponents = normalizedComponents
        if mutableComponents.path.isEmpty {
            mutableComponents.path = ""
        }

        guard let url = mutableComponents.url else {
            throw APIError.validationFailed("The address is not valid.")
        }

        return url
    }
}
