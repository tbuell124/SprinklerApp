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

/// Protocol describing the discovery interface used by the app.
protocol BonjourDiscoveryProviding: AnyObject {
    /// Publisher emitting currently discovered devices.
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { get }
    /// Starts Bonjour discovery.
    func start()
    /// Stops Bonjour discovery.
    func stop()
    /// Refreshes the discovery session.
    func refresh()
}

/// Stubbed discovery service that keeps the project building even without Bonjour integration.
final class BonjourDiscoveryService: BonjourDiscoveryProviding {
    private let subject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { subject.eraseToAnyPublisher() }

    func start() { /* TODO: Implement NetServiceBrowser */ }
    func stop()  { /* noop */ }
    func refresh() { start() }
}
