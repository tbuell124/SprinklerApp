import Foundation
import Dispatch
#if canImport(Combine)
import Combine
#endif

/// Bridges the Bonjour discovery service to SwiftUI-friendly published properties.
@MainActor
final class DiscoveryViewModel: ObservableObject {
    /// Devices currently discovered on the network.
    @Published var devices: [DiscoveredDevice] = []
    /// Whether discovery is currently active to help drive UI state.
    @Published var isBrowsing: Bool = false
    /// Optional error message that can be surfaced to the user.
    @Published var errorMessage: String?

    private let service: BonjourDiscoveryProviding
    #if canImport(Combine)
    private var cancellables = Set<AnyCancellable>()
    #endif

    init(service: BonjourDiscoveryProviding = BonjourDiscoveryService()) {
        self.service = service
        #if canImport(Combine)
        service.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.devices = $0 }
            .store(in: &cancellables)

        service.isBrowsingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isBrowsing = $0 }
            .store(in: &cancellables)

        service.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.errorMessage = $0 }
            .store(in: &cancellables)
        #endif
    }

    /// Starts discovery and flips the browsing flag.
    func start() {
        isBrowsing = true
        errorMessage = nil
        service.start()
    }

    /// Forces a new discovery pass by calling refresh on the service.
    func refresh() {
        isBrowsing = true
        errorMessage = nil
        service.refresh()
    }

    /// Stops discovery and resets the browsing flag.
    func stop() {
        isBrowsing = false
        service.stop()
    }
}
