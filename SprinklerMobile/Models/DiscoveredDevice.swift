import Foundation

/// Represents a discovered sprinkler controller on the local network.
struct DiscoveredDevice: Identifiable, Equatable {
    /// Unique identifier for the device, typically derived from host/port.
    let id: String
    /// Human-readable device name advertised via Bonjour.
    let name: String
    /// Bonjour-advertised hostname if available.
    let host: String?
    /// Resolved IP address for the device.
    let ip: String?
    /// Listening port for the sprinkler controller API.
    let port: Int

    /// Builds a usable base URL string for making requests to the controller.
    var baseURLString: String {
        if let h = host { return "http://\(h):\(port)" }
        if let ip = ip {
            return ip.contains(":") ? "http://[\(ip)]:\(port)" : "http://\(ip):\(port)"
        }
        return ""
    }
}
