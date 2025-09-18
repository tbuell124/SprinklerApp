import Foundation

#if canImport(Combine)
import Combine
#endif

// MARK: - Public Models

/// Represents a sprinkler controller discovered via Bonjour/mDNS.
public struct DiscoveredDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let host: String?
    public let ip: String?
    public let port: Int

    /// Preferred base URL constructed from the resolved host name or IP address.
    public var baseURLString: String {
        let target = host ?? ip ?? ""
        guard !target.isEmpty else { return "" }

        let needsBrackets = target.contains(":") && !target.hasPrefix("[")
        let hostComponent = needsBrackets ? "[\(target)]" : target
        return "http://\(hostComponent):\(port)"
    }
}

/// Contract adopted by discovery services capable of publishing Bonjour results to observers.
public protocol BonjourDiscoveryProviding: AnyObject {
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { get }
    func start()
    func stop()
    func refresh()
}

/// Additional protocol that surfaces discovery status updates for clients that want to react to
/// permission errors or ongoing searches.
public protocol BonjourDiscoveryStatusPublishing: AnyObject {
    var statusPublisher: AnyPublisher<BonjourDiscoveryStatus, Never> { get }
}

/// Represents the lifecycle of the Bonjour discovery process.
public enum BonjourDiscoveryStatus: Equatable {
    case idle
    case browsing
    case failed(BonjourDiscoveryError)
}

/// Domain specific error surfaced when discovery cannot continue.
public enum BonjourDiscoveryError: Error, Equatable {
    case permissionDenied
    case underlying(String)
}

private enum BonjourDiscoveryFilter {
    private static let keyword = "sprinkler"

    static func matches(name: String, host: String?) -> Bool {
        let lowercasedName = name.lowercased()
        if lowercasedName.contains(keyword) {
            return true
        }

        if let host, host.lowercased().contains(keyword) {
            return true
        }

        return false
    }
}

#if !canImport(Combine)
// Minimal stand-ins so Linux builds of the Swift Package continue to compile even though Combine
// is unavailable. The iOS application targets the real Combine framework so these types are never
// exercised in production.
public struct AnyPublisher<Output, Failure: Error> {
    public init() {}
}
#endif

// MARK: - Bonjour Discovery Implementation

#if canImport(Darwin) && canImport(Combine)
import Darwin
import CFNetwork

@MainActor
public final class BonjourDiscoveryService: NSObject, BonjourDiscoveryProviding, BonjourDiscoveryStatusPublishing {
    private enum Constants {
        static let serviceTypes = ["_sprinkler._tcp.", "_http._tcp."]
        static let resolveTimeout: TimeInterval = 5.0
        static let localDomain = ""
    }

    private struct ServiceRecord {
        let service: NetService
        var hostName: String?
        var ipv4: String?
        var ipv6: String?
    }

    private let devicesSubject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    private let statusSubject = CurrentValueSubject<BonjourDiscoveryStatus, Never>(.idle)

    private var browsers: [NetServiceBrowser] = []
    private var records: [ObjectIdentifier: ServiceRecord] = [:]
    private var isRunning = false

    public override init() {
        super.init()
    }

    // MARK: BonjourDiscoveryProviding

    public var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> {
        devicesSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    public func start() {
        guard !isRunning else { return }
        beginBrowsing(resetResults: false)
    }

    public func refresh() {
        beginBrowsing(resetResults: true)
    }

    public func stop() {
        guard isRunning else { return }
        stopBrowsing()
        statusSubject.send(.idle)
    }

    // MARK: BonjourDiscoveryStatusPublishing

    public var statusPublisher: AnyPublisher<BonjourDiscoveryStatus, Never> {
        statusSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: Private helpers

    private func beginBrowsing(resetResults: Bool) {
        stopBrowsing()

        if resetResults {
            records.removeAll()
            devicesSubject.send([])
        }

        isRunning = true
        statusSubject.send(.browsing)

        Constants.serviceTypes.forEach { type in
            let browser = NetServiceBrowser()
            browser.includesPeerToPeer = true
            browser.delegate = self
            browser.schedule(in: .main, forMode: .default)
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: Constants.localDomain)
        }
    }

    private func stopBrowsing() {
        browsers.forEach { browser in
            browser.stop()
            browser.delegate = nil
        }
        browsers.removeAll()
        isRunning = false
    }

    private func updateRecord(for service: NetService, host: String?, ipv4: String?, ipv6: String?) {
        let identifier = ObjectIdentifier(service)
        var record = records[identifier] ?? ServiceRecord(service: service, hostName: nil, ipv4: nil, ipv6: nil)

        if let host = host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
            record.hostName = host
        }
        if let ipv4 { record.ipv4 = ipv4 }
        if let ipv6 { record.ipv6 = ipv6 }

        records[identifier] = record
        publishDevices()
    }

    private func removeRecord(for service: NetService) {
        let identifier = ObjectIdentifier(service)
        records.removeValue(forKey: identifier)
        publishDevices()
    }

    private func publishDevices() {
        var deduplicated: [String: DiscoveredDevice] = [:]

        for record in records.values {
            guard let device = Self.makeDevice(from: record) else { continue }
            deduplicated[device.id] = device
        }

        let sorted = deduplicated.values.sorted { lhs, rhs in
            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            let lhsDetail = lhs.host ?? lhs.ip ?? ""
            let rhsDetail = rhs.host ?? rhs.ip ?? ""
            return lhsDetail.localizedCaseInsensitiveCompare(rhsDetail) == .orderedAscending
        }

        devicesSubject.send(Array(sorted))
    }

    private static func makeDevice(from record: ServiceRecord) -> DiscoveredDevice? {
        let service = record.service
        let port = service.port
        guard port > 0 else { return nil }

        let host = sanitizedHostName(from: record)
        let ip = record.ipv4 ?? record.ipv6

        guard BonjourDiscoveryFilter.matches(name: service.name, host: host) else { return nil }

        let identifierSource = host ?? service.name
        let id = "\(identifierSource):\(port)"
        return DiscoveredDevice(
            id: id,
            name: service.name,
            host: host,
            ip: ip,
            port: port
        )
    }

    static func sanitizedHostName(from record: ServiceRecord) -> String? {
        if let host = record.hostName, !host.isEmpty {
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        if let resolved = record.service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !resolved.isEmpty {
            return resolved
        }
        return nil
    }

    private func handleSearchError(_ errorDict: [String: NSNumber]) {
        defer { stopBrowsing() }

        guard
            let codeValue = errorDict[NSNetServicesErrorCode],
            let errorCode = CFNetServicesError(rawValue: codeValue.int32Value)
        else {
            statusSubject.send(.failed(.underlying("Unknown discovery error.")))
            return
        }

        if errorCode == .security {
            statusSubject.send(.failed(.permissionDenied))
        } else {
            statusSubject.send(.failed(.underlying("Discovery failed with error code \(errorCode.rawValue).")))
        }
    }

    private func resolveAddresses(for service: NetService) {
        service.delegate = self
        service.includesPeerToPeer = true
        service.schedule(in: .main, forMode: .default)
        service.resolve(withTimeout: Constants.resolveTimeout)
        records[ObjectIdentifier(service)] = ServiceRecord(service: service, hostName: nil, ipv4: nil, ipv6: nil)
    }

    private func processResolvedAddresses(for service: NetService) {
        guard let addresses = service.addresses, !addresses.isEmpty else {
            updateRecord(for: service, host: service.hostName, ipv4: nil, ipv6: nil)
            return
        }

        var ipv4: String?
        var ipv6: String?

        for data in addresses {
            guard let ipAddress = Self.ipAddress(from: data) else { continue }
            switch ipAddress.kind {
            case .ipv4:
                if ipv4 == nil { ipv4 = ipAddress.value }
            case .ipv6:
                if ipv6 == nil { ipv6 = ipAddress.value }
            }
        }

        updateRecord(for: service, host: service.hostName, ipv4: ipv4, ipv6: ipv6)
    }

    private static func ipAddress(from data: Data) -> (value: String, kind: IPKind)? {
        return data.withUnsafeBytes { rawPointer -> (String, IPKind)? in
            guard let baseAddress = rawPointer.baseAddress else { return nil }
            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
            switch Int32(sockaddrPointer.pointee.sa_family) {
            case AF_INET:
                var address = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return (String(cString: buffer), .ipv4)
            case AF_INET6:
                var address = sockaddrPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                return (String(cString: buffer), .ipv6)
            default:
                return nil
            }
        }
    }

    private enum IPKind {
        case ipv4
        case ipv6
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourDiscoveryService: NetServiceBrowserDelegate {
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolveAddresses(for: service)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        removeRecord(for: service)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        handleSearchError(errorDict)
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        if isRunning {
            statusSubject.send(.idle)
            isRunning = false
        }
    }
}

// MARK: - NetServiceDelegate

extension BonjourDiscoveryService: NetServiceDelegate {
    public func netServiceDidResolveAddress(_ sender: NetService) {
        processResolvedAddresses(for: sender)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        removeRecord(for: sender)
    }
}

#else

// MARK: - Stub implementation for non-Darwin platforms or when Combine is unavailable.

public final class BonjourDiscoveryService: BonjourDiscoveryProviding, BonjourDiscoveryStatusPublishing {
    public init() {}

    public var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { AnyPublisher() }
    public var statusPublisher: AnyPublisher<BonjourDiscoveryStatus, Never> { AnyPublisher() }

    public func start() {}
    public func stop() {}
    public func refresh() {}
}

#endif

extension BonjourDiscoveryService {
    static func isSprinklerService(name: String, host: String?) -> Bool {
        BonjourDiscoveryFilter.matches(name: name, host: host)
    }
}
