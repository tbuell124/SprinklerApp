import Foundation
import Combine

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isBrowsing: Bool = false
    @Published var errorMessage: String?

    private let discoveryService: BonjourDiscoveryProviding
    private var cancellables: Set<AnyCancellable> = []
    private weak var connectivityStore: ConnectivityStore?
    private var hasStarted = false

    init(discoveryService: BonjourDiscoveryProviding = BonjourDiscoveryService()) {
        self.discoveryService = discoveryService
        observeDiscoveryUpdates()
    }

    func attach(connectivityStore: ConnectivityStore) {
        self.connectivityStore = connectivityStore
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        errorMessage = nil
        isBrowsing = true
        discoveryService.start()
    }

    func refresh() {
        errorMessage = nil
        isBrowsing = true
        discoveryService.refresh()
    }

    func stop() {
        discoveryService.stop()
        isBrowsing = false
        hasStarted = false
    }

    func select(device: DiscoveredDevice) {
        guard let store = connectivityStore else { return }
        store.baseURLString = device.baseURLString
        Task { await store.testConnection() }
    }

    // MARK: Private helpers

    private func observeDiscoveryUpdates() {
        discoveryService.devicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.devices = devices
            }
            .store(in: &cancellables)

        if let statusPublisher = (discoveryService as? BonjourDiscoveryStatusPublishing)?.statusPublisher {
            statusPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.handle(status: status)
                }
                .store(in: &cancellables)
        }
    }

    private func handle(status: BonjourDiscoveryStatus) {
        switch status {
        case .idle:
            isBrowsing = false
        case .browsing:
            isBrowsing = true
        case let .failed(error):
            isBrowsing = false
            switch error {
            case .permissionDenied:
                errorMessage = "Local Network permission is required to find devices. You can enter a URL manually, or enable local network access in Settings."
            case let .underlying(message):
                errorMessage = message
            }
        }
    }
}
