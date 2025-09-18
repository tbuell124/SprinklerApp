import Foundation
#if canImport(Combine)
import Combine
#else
public struct AnyPublisher<Output, Failure: Error> {
    public init() {}
}

final class CurrentValueSubject<Output, Failure: Error> {
    private var value: Output

    init(_ value: Output) { self.value = value }

    func send(_ value: Output) { self.value = value }

    func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> { AnyPublisher() }
}
#endif

struct DiscoveredDevice: Identifiable, Equatable {
    let id: String         // "\(host ?? name):\(port)"
    let name: String
    let host: String?
    let ip: String?
    let port: Int

    var baseURLString: String {
        if let h = host { return "http://\(h):\(port)" }
        if let ip = ip {
            // bracket IPv6
            if ip.contains(":") { return "http://[\(ip)]:\(port)" }
            return "http://\(ip):\(port)"
        }
        return ""
    }
}

protocol BonjourDiscoveryProviding: AnyObject {
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { get }
    func start()
    func stop()
    func refresh()
}

/// Build that **always compiles**. If Bonjour is unavailable or permission is denied,
/// we still provide a no-op implementation so app builds & runs.
final class BonjourDiscoveryService: BonjourDiscoveryProviding {
    private let subject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { subject.eraseToAnyPublisher() }

    func start() { /* real impl may go here; stub OK for build */ }
    func stop()  { /* noop */ }
    func refresh() { start() }
}
