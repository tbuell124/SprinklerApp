import Foundation

enum Validators {
    private static let allowedSchemes: Set<String> = ["http", "https"]

    /// Normalizes a base address entered by the user into a canonical URL that the rest of the
    /// networking stack can safely reuse.
    /// - Parameters:
    ///   - rawValue: The raw, user supplied string.
    ///   - restrictToLocalNetwork: When `true`, IPv4 entries must be within RFC1918 ranges and
    ///   IPv6 entries must be loopback or unique/local scope. Hostnames without a TLD are treated
    ///   as LAN entries. Pass `false` to allow any well formed host.
    /// - Returns: A normalized URL ready to persist and reuse.
    static func normalizeBaseAddress(_ rawValue: String,
                                     restrictToLocalNetwork: Bool = true) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validationFailed("Please enter the sprinkler controller address.")
        }

        let preparedValue = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: preparedValue) else {
            throw APIError.validationFailed("The address could not be parsed.")
        }

        if components.scheme?.isEmpty ?? true {
            components.scheme = "http"
        }

        components.scheme = components.scheme?.lowercased()
        guard let scheme = components.scheme, allowedSchemes.contains(scheme) else {
            throw APIError.validationFailed("The address must start with http:// or https://.")
        }

        guard components.user == nil, components.password == nil else {
            throw APIError.validationFailed("Usernames and passwords are not supported in the address.")
        }

        if let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            components.host = host.lowercased()
        }

        guard let host = components.host, !host.isEmpty else {
            throw APIError.validationFailed("Please include the host or IP address.")
        }

        if restrictToLocalNetwork, !isHostAllowedOnLocalNetwork(host) {
            throw APIError.validationFailed("Please enter a local network address (e.g. 10.x.x.x, 172.16-31.x.x, or 192.168.x.x).")
        }

        if let port = components.port,
           let defaultPort = defaultPort(forScheme: scheme),
           port == defaultPort {
            components.port = nil
        }

        if components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/" {
            components.percentEncodedPath = ""
        }
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw APIError.validationFailed("The address is not valid.")
        }

        return url
    }

    private static func defaultPort(forScheme scheme: String) -> Int? {
        switch scheme {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    private static func isHostAllowedOnLocalNetwork(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" {
            return true
        }

        if host.hasSuffix(".local") || host.hasSuffix(".lan") {
            return true
        }

        if !host.contains(".") && !host.contains(":") {
            return true
        }

        if let octets = ipv4Octets(for: host) {
            return isRFC1918(octets)
        }

        if host.contains(":") {
            return isLocalIPv6(host)
        }

        return false
    }

    private static func ipv4Octets(for host: String) -> [UInt8]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)

        for part in parts {
            guard let value = UInt8(part) else { return nil }
            octets.append(value)
        }

        return octets
    }

    private static func isRFC1918(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        switch octets[0] {
        case 10:
            return true
        case 172 where (16...31).contains(octets[1]):
            return true
        case 192 where octets[1] == 168:
            return true
        default:
            return false
        }
    }

    private static func isLocalIPv6(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "::1" || normalized.hasPrefix("fe80") || normalized.hasPrefix("fd") || normalized.hasPrefix("fc")
    }
}
