import Foundation
#if canImport(Combine)
import Combine
#endif

/// Abstracts Bonjour discovery so the view model can react to updates through Combine.
protocol BonjourDiscoveryProviding: AnyObject {
    /// Publisher emitting current list of discovered sprinkler controllers.
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { get }
    /// Starts Bonjour discovery.
    func start()
    /// Stops the ongoing discovery session and clears cached data.
    func stop()
    /// Requests a fresh discovery run.
    func refresh()
}

#if canImport(Combine) && !os(Linux)
#if canImport(Darwin)
import Darwin
#endif

/// Concrete Bonjour discovery implementation that publishes controller devices discovered on the LAN.
final class BonjourDiscoveryService: NSObject, BonjourDiscoveryProviding {
    private let browser: NetServiceBrowser
    private let subject: CurrentValueSubject<[DiscoveredDevice], Never>
    private var services: [String: NetService]
    private var devices: [String: DiscoveredDevice]
    private var isSearching: Bool
    private var pendingRestart: Bool

    override init() {
        browser = NetServiceBrowser()
        subject = CurrentValueSubject<[DiscoveredDevice], Never>([])
        services = [:]
        devices = [:]
        isSearching = false
        pendingRestart = false
        super.init()
        browser.delegate = self
        browser.includesPeerToPeer = true
    }

    /// Provides the current set of discovered devices to observers.
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> {
        subject.eraseToAnyPublisher()
    }

    /// Starts Bonjour discovery when not already running.
    func start() {
        performOnMain { [weak self] in
            self?.startUnsafe()
        }
    }

    /// Stops discovery, clearing any cached results.
    func stop() {
        performOnMain { [weak self] in
            self?.stopUnsafe(clearResults: true, forRestart: false)
        }
    }

    /// Restarts discovery by stopping and starting a fresh search once the previous search ends.
    func refresh() {
        performOnMain { [weak self] in
            guard let self else { return }
            let wasSearching = self.isSearching
            self.stopUnsafe(clearResults: true, forRestart: wasSearching)
            if !wasSearching {
                self.startUnsafe()
            }
        }
    }

    /// Ensures work runs on the main thread because NetServiceBrowser expects to be driven there.
    private func performOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    /// Starts the underlying browser if it is not already searching.
    private func startUnsafe() {
        guard !isSearching else { return }
        isSearching = true
        browser.searchForServices(ofType: "_sprinkler._tcp.", inDomain: "local.")
    }

    /// Stops the underlying browser and optionally requests a restart after it finishes shutting down.
    private func stopUnsafe(clearResults: Bool, forRestart: Bool) {
        pendingRestart = forRestart
        browser.stop()
        isSearching = false
        guard clearResults else { return }
        services.values.forEach { $0.stop() }
        services.removeAll()
        devices.removeAll()
        publishDevices()
    }

    /// Publishes discovered devices sorted by name for consistent UI ordering.
    private func publishDevices() {
        let sorted = devices.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        subject.send(sorted)
    }

    /// Updates (or removes) a device associated with the provided service.
    private func updateDevice(for service: NetService) {
        let key = Self.serviceKey(for: service)
        guard let device = Self.makeDevice(from: service) else {
            devices.removeValue(forKey: key)
            return
        }
        devices[key] = device
    }

    /// Generates a unique key for the NetService so entries can be tracked across delegate callbacks.
    private static func serviceKey(for service: NetService) -> String {
        "\(service.name).\(service.type)\(service.domain)"
    }

    /// Attempts to create a `DiscoveredDevice` from a resolved NetService.
    private static func makeDevice(from service: NetService) -> DiscoveredDevice? {
        guard service.port > 0 else { return nil }
        let trimmedHost = service.hostName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmedHost?.isEmpty == false ? trimmedHost : nil
        let ip = Self.extractIPAddress(from: service.addresses)

        guard let identifierSource = host ?? ip else { return nil }
        let id = "\(identifierSource):\(service.port)"
        return DiscoveredDevice(id: id, name: service.name, host: host, ip: ip, port: service.port)
    }

    /// Extracts a numeric IP address from the resolved socket addresses, preferring IPv4 when available.
    private static func extractIPAddress(from addresses: [Data]?) -> String? {
        guard let addresses, !addresses.isEmpty else { return nil }

        var ipv6Fallback: String?
        for data in addresses {
            guard let (family, ip) = ipAddress(from: data), let ip else { continue }
            if family == sa_family_t(AF_INET) {
                return ip
            }
            if family == sa_family_t(AF_INET6) {
                ipv6Fallback = ipv6Fallback ?? ip
            }
        }
        return ipv6Fallback
    }

    /// Converts a sockaddr data blob into a tuple describing its family and numeric host string.
    private static func ipAddress(from data: Data) -> (sa_family_t, String?)? {
        return data.withUnsafeBytes { pointer -> (sa_family_t, String?)? in
            guard let addressPtr = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
            let family = addressPtr.pointee.sa_family
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPtr,
                socklen_t(data.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { return (family, nil) }
            return (family, String(cString: hostBuffer))
        }
    }
}

extension BonjourDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services[Self.serviceKey(for: service)] = service
        service.resolve(withTimeout: 5)
        if !moreComing {
            publishDevices()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: Self.serviceKey(for: service))
        devices.removeValue(forKey: Self.serviceKey(for: service))
        if !moreComing {
            publishDevices()
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
        if pendingRestart {
            pendingRestart = false
            startUnsafe()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        pendingRestart = false
        isSearching = false
    }
}

extension BonjourDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        updateDevice(for: sender)
        publishDevices()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        devices.removeValue(forKey: Self.serviceKey(for: sender))
        publishDevices()
    }
}

#else

/// Lightweight stand-ins for Combine types so the Linux build does not fail.
public struct AnyPublisher<Output, Failure: Error> {
    public init() {}
}

final class CurrentValueSubject<Output, Failure: Error> {
    private var value: Output

    init(_ value: Output) { self.value = value }

    func send(_ value: Output) { self.value = value }

    func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher() }
}

/// Stub implementation for Linux where Bonjour discovery APIs are unavailable.
final class BonjourDiscoveryService: BonjourDiscoveryProviding {
    private let subject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { subject.eraseToAnyPublisher() }

    func start() {}
    func stop() {}
    func refresh() {}
}

#endif
