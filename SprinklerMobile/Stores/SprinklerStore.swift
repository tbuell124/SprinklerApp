import Foundation
import Combine

@MainActor
final class SprinklerStore: ObservableObject {
    enum ConnectionStatus: Equatable {
        case idle
        case connecting
        case connected(Date)
        case unreachable(String)

        var bannerText: String {
            switch self {
            case .idle: return "Set Target IP"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .unreachable: return "Unreachable"
            }
        }

        var isReachable: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // Remote resources
    @Published private(set) var pins: [PinDTO] = []
    var activePins: [PinDTO] {
        pins.filter { $0.isEnabled ?? true }
    }
    @Published private(set) var schedules: [ScheduleDTO] = []
    @Published private(set) var scheduleGroups: [ScheduleGroupDTO] = []
    @Published private(set) var rain: RainDTO?

    // Connection state
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var isRefreshing: Bool = false
    @Published var toast: ToastState?

    // Settings state
    @Published var targetAddress: String
    @Published var validationError: String?
    @Published private(set) var resolvedBaseURL: URL?
    @Published var isTestingConnection: Bool = false
    @Published var lastSuccessfulConnection: Date?
    @Published var lastFailure: APIError?
    @Published var serverVersion: String?

    private let client: APIClient
    private let defaults: UserDefaults
    private let keychain: KeychainStoring

    private let targetKey = "sprinkler.target_address"
    private let keychainTargetKey = "sprinkler.target_address_secure"
    private let lastSuccessKey = "sprinkler.last_success"
    private let versionKey = "sprinkler.server_version"

    init(userDefaults: UserDefaults = .standard,
         keychain: KeychainStoring = KeychainStorage(),
         client: APIClient = APIClient()) {
        self.defaults = userDefaults
        self.keychain = keychain
        self.client = client

        let keychainValue = keychain.string(forKey: keychainTargetKey)
        let defaultsValue = userDefaults.string(forKey: targetKey)

        if keychainValue == nil, let defaultsValue {
            try? keychain.set(defaultsValue, forKey: keychainTargetKey)
            userDefaults.removeObject(forKey: targetKey)
        }

        let savedAddress = keychainValue ?? defaultsValue ?? ""
        self.targetAddress = savedAddress
        self.validationError = nil
        self.resolvedBaseURL = try? Validators.normalizeBaseAddress(savedAddress)
        self.lastSuccessfulConnection = userDefaults.object(forKey: lastSuccessKey) as? Date
        self.serverVersion = userDefaults.string(forKey: versionKey)

        if let baseURL = resolvedBaseURL {
            Task { await client.updateBaseURL(baseURL) }
            if let lastSuccessfulConnection {
                connectionStatus = .connected(lastSuccessfulConnection)
            }
        }
    }

    func refresh() async {
        guard resolvedBaseURL != nil else { return }
        isRefreshing = true
        connectionStatus = .connecting
        defer { isRefreshing = false }
        do {
            let status = try await client.fetchStatus()
            apply(status: status)
            connectionStatus = .connected(Date())
            recordConnectionSuccess(version: status.version)
        } catch let error as APIError {
            connectionStatus = .unreachable(error.localizedDescription)
            recordConnectionFailure(error)
            showToast(message: error.localizedDescription, style: .error)
        } catch {
            let apiError = APIError.invalidResponse
            connectionStatus = .unreachable(apiError.localizedDescription)
            recordConnectionFailure(apiError)
            showToast(message: apiError.localizedDescription, style: .error)
        }
    }

    func saveAndTestTarget() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            let url = try resolveCurrentAddress()
            await client.updateBaseURL(url)
            await refresh()
        } catch let error as APIError {
            setValidationError(error)
            recordConnectionFailure(error)
            connectionStatus = .unreachable(error.localizedDescription)
        } catch {
            let apiError = APIError.invalidURL
            setValidationError(apiError)
            recordConnectionFailure(apiError)
            connectionStatus = .unreachable(apiError.localizedDescription)
        }
    }

    func togglePin(_ pin: PinDTO, to desiredState: Bool) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let previousState = pins[index].isActive
        pins[index].isActive = desiredState

        Task {
            do {
                try await client.setPin(pin.pin, on: desiredState)
            } catch {
                await MainActor.run {
                    if let revertIndex = pins.firstIndex(where: { $0.id == pin.id }) {
                        pins[revertIndex].isActive = previousState
                    }
                    showToast(message: "Failed to update pin", style: .error)
                }
            }
        }
    }

    func renamePin(_ pin: PinDTO, newName: String) {
        let normalizedName = normalizedName(from: newName)
        Task {
            do {
                let isEnabled = pins.first(where: { $0.id == pin.id })?.isEnabled ?? pin.isEnabled ?? true
                try await client.updatePin(pin.pin, name: normalizedName, isEnabled: isEnabled)
                await MainActor.run {
                    if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                        pins[index].name = normalizedName
                    }
                    showToast(message: "Pin renamed", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Rename failed", style: .error)
                }
            }
        }
    }

    func setPinEnabled(_ pin: PinDTO, isEnabled: Bool) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let previous = pins[index]
        pins[index].isEnabled = isEnabled

        let normalizedName = normalizedName(from: pins[index].name)
        Task {
            do {
                try await client.updatePin(pin.pin, name: normalizedName, isEnabled: isEnabled)
                await MainActor.run {
                    showToast(message: isEnabled ? "Pin enabled" : "Pin hidden", style: .success)
                }
            } catch {
                await MainActor.run {
                    if let revertIndex = pins.firstIndex(where: { $0.id == pin.id }) {
                        pins[revertIndex] = previous
                    }
                    showToast(message: "Failed to update pin", style: .error)
                }
            }
        }
    }

    func setRain(active: Bool, durationHours: Int?) {
        Task {
            do {
                try await client.setRain(isActive: active, durationHours: durationHours)
                await refresh()
                await MainActor.run {
                    showToast(message: "Rain delay updated", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to update rain delay", style: .error)
                }
            }
        }
    }

    func upsertSchedule(_ draft: ScheduleDraft) {
        Task {
            do {
                if schedules.contains(where: { $0.id == draft.id }) {
                    try await client.updateSchedule(id: draft.id, schedule: draft.payload)
                } else {
                    try await client.createSchedule(draft.payload)
                }
                await refresh()
                await MainActor.run {
                    showToast(message: "Schedule saved", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to save schedule", style: .error)
                }
            }
        }
    }

    func deleteSchedule(_ schedule: ScheduleDTO) {
        Task {
            do {
                try await client.deleteSchedule(id: schedule.id)
                await refresh()
                await MainActor.run {
                    showToast(message: "Schedule deleted", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Unable to delete schedule", style: .error)
                }
            }
        }
    }

    func reorderSchedules(from offsets: IndexSet, to destination: Int) {
        var reordered = schedules
        reordered.move(fromOffsets: offsets, toOffset: destination)
        schedules = reordered
        Task {
            do {
                let order = reordered.map { $0.id }
                try await client.reorderSchedules(order)
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to reorder schedules", style: .error)
                }
            }
        }
    }

    func reorderPins(from offsets: IndexSet, to destination: Int) {
        let currentActive = activePins
        var reorderedActive = currentActive
        reorderedActive.move(fromOffsets: offsets, toOffset: destination)

        var combined: [PinDTO] = []
        var iterator = reorderedActive.makeIterator()
        for pin in pins {
            if pin.isEnabled ?? true, let next = iterator.next() {
                combined.append(next)
            } else {
                combined.append(pin)
            }
        }

        pins = combined
        Task {
            do {
                let order = combined.map { $0.pin }
                try await client.reorderPins(order)
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to reorder pins", style: .error)
                }
            }
        }
    }

    func loadScheduleGroups() async {
        do {
            let groups = try await client.fetchScheduleGroups()
            scheduleGroups = groups
        } catch {
            showToast(message: "Unable to load groups", style: .error)
        }
    }

    func createScheduleGroup(name: String) {
        Task {
            do {
                try await client.createScheduleGroup(name: name)
                await loadScheduleGroups()
                await MainActor.run {
                    showToast(message: "Group created", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to create group", style: .error)
                }
            }
        }
    }

    func selectScheduleGroup(id: String) {
        Task {
            do {
                try await client.selectScheduleGroup(id: id)
                await refresh()
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to select group", style: .error)
                }
            }
        }
    }

    func addAllToGroup(id: String) {
        Task {
            do {
                try await client.addAllToGroup(id: id)
                await refresh()
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to add all", style: .error)
                }
            }
        }
    }

    func deleteScheduleGroup(id: String) {
        Task {
            do {
                try await client.deleteScheduleGroup(id: id)
                await loadScheduleGroups()
                await MainActor.run {
                    showToast(message: "Group deleted", style: .success)
                }
            } catch {
                await MainActor.run {
                    showToast(message: "Failed to delete group", style: .error)
                }
            }
        }
    }

    func resolveCurrentAddress() throws -> URL {
        let url = try Validators.normalizeBaseAddress(targetAddress)
        validationError = nil
        if resolvedBaseURL != url {
            resolvedBaseURL = url
        }
        persistTargetAddress(targetAddress)
        return url
    }

    func setValidationError(_ error: APIError) {
        if case let .validationFailed(message) = error {
            validationError = message
        } else {
            validationError = error.localizedDescription
        }
    }

    func recordConnectionSuccess(version: String?) {
        lastSuccessfulConnection = Date()
        lastFailure = nil
        defaults.set(lastSuccessfulConnection, forKey: lastSuccessKey)
        if let version {
            serverVersion = version
            defaults.set(version, forKey: versionKey)
        }
    }

    func recordConnectionFailure(_ error: APIError) {
        lastFailure = error
    }

    private func persistTargetAddress(_ address: String) {
        do {
            try keychain.set(address, forKey: keychainTargetKey)
            defaults.removeObject(forKey: targetKey)
        } catch {
            defaults.set(address, forKey: targetKey)
        }
    }

    private func apply(status: StatusDTO) {
        assignIfDifferent(\SprinklerStore.pins, to: status.pins ?? [])
        assignIfDifferent(\SprinklerStore.schedules, to: status.schedules ?? [])
        assignIfDifferent(\SprinklerStore.scheduleGroups, to: status.scheduleGroups ?? [])
        assignIfDifferent(\SprinklerStore.rain, to: status.rain)
    }

    private func normalizedName(from name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedName(from name: String?) -> String? {
        guard let name else { return nil }
        return normalizedName(from: name)
    }

    private func showToast(message: String, style: ToastState.Style) {
        toast = ToastState(message: message, style: style)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.message == message {
                toast = nil
            }
        }
    }

    private func assignIfDifferent<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SprinklerStore, Value>, to newValue: Value) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }
}
