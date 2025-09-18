import Foundation
import Dispatch
#if canImport(Combine)
import Combine
#endif

/// Bridges Bonjour discovery events into SwiftUI-friendly published properties.
@MainActor
final class DiscoveryViewModel: ObservableObject {
    /// Discovered devices surfaced to the UI.
    @Published var devices: [DiscoveredDevice] = []
    /// Indicates whether discovery is currently active.
    @Published var isBrowsing: Bool = false
    /// Holds any user-facing error message from discovery.
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
        #endif
    }

    /// Starts Bonjour discovery and flips the state flag.
    func start() {
        isBrowsing = true
        service.start()
    }

    /// Requests a refresh from the service, typically re-browsing.
    func refresh() {
        isBrowsing = true
        service.refresh()
    }

    /// Stops discovery and resets the browsing flag.
    func stop() {
        isBrowsing = false
        service.stop()
    }
}
