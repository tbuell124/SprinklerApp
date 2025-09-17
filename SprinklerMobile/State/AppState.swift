import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
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

    @Published private(set) var pins: [PinDTO] = []
    @Published private(set) var schedules: [ScheduleDTO] = []
    @Published private(set) var scheduleGroups: [ScheduleGroupDTO] = []
    @Published private(set) var rain: RainDTO?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var isRefreshing: Bool = false
    @Published var toast: ToastState?

    let settings: SettingsStore
    private let client: APIClient
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, client: APIClient = APIClient()) {
        self.settings = settings
        self.client = client

        if let base = settings.resolvedBaseURL {
            Task { await client.updateBaseURL(base) }
            if let last = settings.lastSuccessfulConnection {
                connectionStatus = .connected(last)
            } else {
                connectionStatus = .idle
            }
        }

        settings.$resolvedBaseURL
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] url in
                guard let self else { return }
                Task { await self.client.updateBaseURL(url) }
            }
            .store(in: &cancellables)
    }

    func refresh() async {
        guard settings.resolvedBaseURL != nil else { return }
        isRefreshing = true
        connectionStatus = .connecting
        defer { isRefreshing = false }
        do {
            let status = try await client.fetchStatus()
            apply(status: status)
            connectionStatus = .connected(Date())
            settings.recordConnectionSuccess(version: status.version)
        } catch let error as APIError {
            connectionStatus = .unreachable(error.localizedDescription)
            settings.recordConnectionFailure(error)
            showToast(message: error.localizedDescription, style: .error)
        } catch {
            let apiError = APIError.invalidResponse
            connectionStatus = .unreachable(apiError.localizedDescription)
            settings.recordConnectionFailure(apiError)
            showToast(message: apiError.localizedDescription, style: .error)
        }
    }

    func saveAndTestTarget() async {
        settings.isTestingConnection = true
        defer { settings.isTestingConnection = false }
        do {
            let url = try settings.resolveCurrentAddress()
            await client.updateBaseURL(url)
            await refresh()
        } catch let error as APIError {
            settings.setValidationError(error)
            settings.recordConnectionFailure(error)
            connectionStatus = .unreachable(error.localizedDescription)
        } catch {
            let apiError = APIError.invalidURL
            settings.setValidationError(apiError)
            settings.recordConnectionFailure(apiError)
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
        Task {
            do {
                try await client.renamePin(pin.pin, name: newName)
                await MainActor.run {
                    if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                        pins[index].name = newName
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
        var reordered = pins
        reordered.move(fromOffsets: offsets, toOffset: destination)
        pins = reordered
        Task {
            do {
                let order = reordered.map { $0.pin }
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

    private func apply(status: StatusDTO) {
        assignIfDifferent(\AppState.pins, to: status.pins ?? [])
        assignIfDifferent(\AppState.schedules, to: status.schedules ?? [])
        assignIfDifferent(\AppState.scheduleGroups, to: status.scheduleGroups ?? [])
        assignIfDifferent(\AppState.rain, to: status.rain)
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

    private func assignIfDifferent<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>, to newValue: Value) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }
}
