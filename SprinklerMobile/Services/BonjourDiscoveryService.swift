import Foundation
#if canImport(Combine)
import Combine
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
#endif

/// Abstracts Bonjour discovery so the view model can react to changes through Combine.
protocol BonjourDiscoveryProviding: AnyObject {
    /// Publisher emitting current list of discovered sprinkler controllers.
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { get }
    /// Starts Bonjour discovery.
    func start()
    /// Stops the ongoing discovery session.
    func stop()
    /// Requests a fresh discovery run.
    func refresh()
}

/// Stubbed implementation that keeps the project compiling while discovery is being built out.
final class BonjourDiscoveryService: BonjourDiscoveryProviding {
    private let subject = CurrentValueSubject<[DiscoveredDevice], Never>([])
    var devicesPublisher: AnyPublisher<[DiscoveredDevice], Never> { subject.eraseToAnyPublisher() }

    func start() { /* TODO: Implement NetServiceBrowser */ }
    func stop()  { /* noop */ }
    func refresh() { start() }
}
