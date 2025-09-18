import Foundation
#if canImport(Combine)
import Combine
#endif

#if !canImport(SwiftUI)
@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    var projectedValue: Published<Value> { self }
}

protocol ObservableObject {}
#endif

#if canImport(Combine)
@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isBrowsing: Bool = false
    @Published var errorMessage: String?

    private let service: BonjourDiscoveryProviding
    private var cancellables = Set<AnyCancellable>()

    init(service: BonjourDiscoveryProviding = BonjourDiscoveryService()) {
        self.service = service
        service.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.devices = $0 }
            .store(in: &cancellables)
    }

    func start() {
        isBrowsing = true
        service.start()
    }

    func refresh() {
        isBrowsing = true
        service.refresh()
    }

    func stop() {
        isBrowsing = false
        service.stop()
    }
}
#else
@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isBrowsing: Bool = false
    @Published var errorMessage: String?

    private let service: BonjourDiscoveryProviding

    init(service: BonjourDiscoveryProviding = BonjourDiscoveryService()) {
        self.service = service
    }

    func start() {
        isBrowsing = true
        service.start()
    }

    func refresh() {
        isBrowsing = true
        service.refresh()
    }

    func stop() {
        isBrowsing = false
        service.stop()
    }
}
#endif
