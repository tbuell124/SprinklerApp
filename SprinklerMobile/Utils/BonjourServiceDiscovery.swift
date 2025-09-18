import Darwin
import Foundation
import Network

/// Represents a discovered sprinkler controller advertised via Bonjour/mDNS.
struct DiscoveredSprinklerService: Identifiable, Equatable {
    /// Stable identifier constructed from the service name and domain information.
    let identifier: String
    /// User-visible service name provided by Bonjour.
    let name: String
    /// Host component resolved for the service.
    let host: NWEndpoint.Host
    /// TCP port the service is listening on.
    let port: NWEndpoint.Port
    /// Potential base URLs for the controller, ordered by preference.
    let candidateURLs: [URL]
    /// IP addresses returned by the Bonjour resolution for diagnostics.
    let ipAddresses: [String]

    var id: String { identifier }

    /// Preferred base URL for the discovered controller.
    var baseURL: URL { candidateURLs[0] }

    /// Alternative URLs (e.g. hostname variants) for the controller.
    var alternativeURLs: [URL] { Array(candidateURLs.dropFirst()) }

    /// User-facing description of the resolved host/port combination.
    var detailDescription: String {
        let hostString: String
        if let firstIP = ipAddresses.first {
            hostString = firstIP
        } else {
            hostString = host.displayString
        }
        return "\(hostString):\(port.rawValue)"
    }
}

/// Discovers sprinkler controllers advertised over Bonjour and publishes updates.
final class BonjourServiceDiscovery: NSObject {
    typealias ServicesUpdateHandler = ([DiscoveredSprinklerService]) -> Void
    typealias StateChangeHandler = (Bool) -> Void

    private let serviceType: String
    private let domain: String
    private let updateHandler: ServicesUpdateHandler
    private let stateHandler: StateChangeHandler

    private let browser: NetServiceBrowser
    private var activeServices: [String: NetService] = [:]
    private var discovered: [String: DiscoveredSprinklerService] = [:]
    private var isSearching: Bool = false

    init(serviceType: String = "_sprinkler._tcp.",
         domain: String = "local.",
         updateHandler: @escaping ServicesUpdateHandler,
         stateHandler: @escaping StateChangeHandler) {
        self.serviceType = serviceType
        self.domain = domain
        self.updateHandler = updateHandler
        self.stateHandler = stateHandler
        self.browser = NetServiceBrowser()
        super.init()
        browser.delegate = self
        browser.includesPeerToPeer = true
    }

    /// Begins the Bonjour discovery process. Subsequent calls while discovery is running are ignored.
    func start() {
        guard !isSearching else { return }
        isSearching = true
        notifyStateChange(isSearching)
        browser.searchForServices(ofType: serviceType, inDomain: domain)
    }

    /// Stops the current Bonjour search and clears any cached results.
    func stop() {
        guard isSearching else { return }
        isSearching = false
        browser.stop()
        activeServices.removeAll()
        discovered.removeAll()
        notifyStateChange(isSearching)
        notifyUpdates()
    }

    private func identifier(for service: NetService) -> String {
        "\(service.name).\(service.domain)"
    }

    private func handleResolution(for service: NetService) {
        let identifier = identifier(for: service)
        guard let resolvedPort = NWEndpoint.Port(rawValue: UInt16(service.port)), resolvedPort.rawValue > 0 else { return }

        let rawHost: String
        if let hostName = service.hostName {
            rawHost = hostName
        } else {
            rawHost = "\(service.name).\(service.domain)"
        }
        let sanitizedHost = sanitizeHostName(rawHost)
        let endpointHost: NWEndpoint.Host
        if let ipv4 = IPv4Address(sanitizedHost) {
            endpointHost = .ipv4(ipv4)
        } else if let ipv6 = IPv6Address(sanitizedHost) {
            endpointHost = .ipv6(ipv6)
        } else {
            endpointHost = .name(sanitizedHost, nil)
        }

        var ipAddresses: [String] = []
        var ipSet: Set<String> = []
        var urlCandidates: [URL] = []
        var urlSet: Set<String> = []

        if let addresses = service.addresses {
            for addressData in addresses {
                guard let ipString = Self.ipAddress(from: addressData) else { continue }
                if !ipSet.contains(ipString) {
                    ipSet.insert(ipString)
                    ipAddresses.append(ipString)
                }
                if let url = Self.httpURL(fromHost: ipString, port: resolvedPort) {
                    let absolute = url.absoluteString
                    if !urlSet.contains(absolute) {
                        urlSet.insert(absolute)
                        urlCandidates.append(url)
                    }
                }
            }
        }

        if let hostURL = Self.httpURL(fromHost: endpointHost.displayString, port: resolvedPort) {
            let absolute = hostURL.absoluteString
            if !urlSet.contains(absolute) {
                urlSet.insert(absolute)
                urlCandidates.append(hostURL)
            }
        }

        guard !urlCandidates.isEmpty else { return }

        let serviceInfo = DiscoveredSprinklerService(identifier: identifier,
                                                     name: service.name,
                                                     host: endpointHost,
                                                     port: resolvedPort,
                                                     candidateURLs: urlCandidates,
                                                     ipAddresses: ipAddresses)
        discovered[identifier] = serviceInfo
        notifyUpdates()
    }

    private func sanitizeHostName(_ host: String) -> String {
        guard host.hasSuffix(".") else { return host }
        return String(host.dropLast())
    }

    private func notifyUpdates() {
        let services = discovered.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [services, handler = updateHandler] in
            handler(services)
        }
    }

    private func notifyStateChange(_ searching: Bool) {
        DispatchQueue.main.async { [handler = stateHandler] in
            handler(searching)
        }
    }

    private static func httpURL(fromHost host: String, port: NWEndpoint.Port) -> URL? {
        let requiresBrackets = host.contains(":") && !host.hasPrefix("[")
        let hostComponent = requiresBrackets ? "[\(host)]" : host
        if port.rawValue > 0 {
            return URL(string: "http://\(hostComponent):\(port.rawValue)")
        } else {
            return URL(string: "http://\(hostComponent)")
        }
    }

    private static func ipAddress(from data: Data) -> String? {
        return data.withUnsafeBytes { rawPointer -> String? in
            guard let baseAddress = rawPointer.baseAddress else { return nil }
            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)

            switch Int32(sockaddrPointer.pointee.sa_family) {
            case AF_INET:
                let ipv4Pointer = UnsafeRawPointer(sockaddrPointer).assumingMemoryBound(to: sockaddr_in.self)
                var address = ipv4Pointer.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            case AF_INET6:
                let ipv6Pointer = UnsafeRawPointer(sockaddrPointer).assumingMemoryBound(to: sockaddr_in6.self)
                var address = ipv6Pointer.pointee.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            default:
                return nil
            }
        }
    }
}

extension BonjourServiceDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        notifyStateChange(true)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
        notifyStateChange(false)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        isSearching = false
        notifyStateChange(false)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let identifier = identifier(for: service)
        activeServices[identifier] = service
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        if !moreComing {
            notifyUpdates()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let identifier = identifier(for: service)
        activeServices.removeValue(forKey: identifier)
        discovered.removeValue(forKey: identifier)
        if !moreComing {
            notifyUpdates()
        }
    }
}

extension BonjourServiceDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        handleResolution(for: sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        activeServices.removeValue(forKey: identifier(for: sender))
    }
}

private extension NWEndpoint.Host {
    var displayString: String {
        switch self {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return address.debugDescription
        case .ipv6(let address):
            return address.debugDescription
        case .unix(let path):
            return path
        case .any:
            return "0.0.0.0"
        @unknown default:
            return ""
        }
    }
}
