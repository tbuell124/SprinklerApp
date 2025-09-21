import Foundation
import Combine
import Network
import Darwin
import SwiftUI

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

    struct ConnectionDiagnostics: Equatable {
        let timestamp: Date
        let latency: TimeInterval
    }

    struct ScheduleRun: Identifiable, Equatable {
        let schedule: Schedule
        let startDate: Date
        let endDate: Date

        var id: String {
            "\(schedule.id)-\(startDate.timeIntervalSince1970)"
        }

        /// Indicates whether the supplied date falls within this run's active window.
        func contains(_ date: Date) -> Bool {
            if endDate <= startDate {
                return abs(date.timeIntervalSince(startDate)) < 60
            }
            return startDate <= date && date < endDate
        }
    }

    // Remote resources
    @Published private(set) var pins: [PinDTO] = PinDTO.makeDefaultSprinklerPins()
    var activePins: [PinDTO] {
        pins.filter { $0.isEnabled ?? true }
    }

    var runningPins: [PinDTO] {
        pins.filter { $0.isActive == true }
    }

    var currentScheduleRun: ScheduleRun? {
        scheduleTimeline(relativeTo: Date()).current
    }

    var nextScheduleRun: ScheduleRun? {
        scheduleTimeline(relativeTo: Date()).next
    }
    @Published private(set) var schedules: [Schedule] = []
    @Published private(set) var rain: RainDTO?
    @Published private(set) var rainAutomationEnabled: Bool = false
    @Published var rainSettingsZip: String = ""
    @Published var rainSettingsThreshold: String = ""
    @Published var rainSettingsIsEnabled: Bool = false
    @Published var isSavingRainSettings: Bool = false
    @Published var isUpdatingRainAutomation: Bool = false
    @Published var manualRainDelayHours: Int
    private var rainSettingsSaveTask: Task<Void, Never>?

    // Connection state
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var isRefreshing: Bool = false
    @Published var toast: ToastState?
    @Published private(set) var connectionDiagnostics: ConnectionDiagnostics?
    @Published var connectionErrorMessage: String?
    @Published private(set) var pendingSyncMessage: String?

    // Settings state
    @Published var targetAddress: String = ""
    @Published var validationError: String?
    @Published private(set) var resolvedBaseURL: URL?
    @Published var isTestingConnection: Bool = false
    @Published var lastSuccessfulConnection: Date?
    @Published var lastFailure: APIError?
    @Published var serverVersion: String?
    @Published private(set) var discoveredServices: [DiscoveredSprinklerService] = []
    @Published private(set) var isDiscoveringServices: Bool = false

    private let client: APIClient
    private let defaults: UserDefaults
    private let keychain: KeychainStoring
    private let statusCache: StatusCache
    private let schedulePersistence: SchedulePersistence
    private var pendingScheduleDeletionIds: Set<String> = []
    private var pendingScheduleReorder: [String]?
    private var pendingOperations: [PendingOperation] = []
    private var isFlushingPendingOperations = false
    private var recentPinToggles: [Int: RecentPinToggle] = [:]

    private enum ScheduleSyncOutcome {
        case synced
        case deferred
        case failed(Error)
    }

    private enum StatusRefreshSource {
        case interactive
        case background
    }

    private struct PendingOperation: Identifiable, Equatable {
        enum Kind: Equatable {
            case setPin(pin: Int, isOn: Bool, minutes: Int?, displayName: String)
            case timedPinRun(pin: Int, durationMinutes: Int, displayName: String)
            case updatePin(pin: Int, name: String?, isEnabled: Bool, displayName: String)
            case reorderPins(order: [Int])
            case setRain(isActive: Bool, durationHours: Int?)
            case updateRainSettings(zip: String, threshold: Int, isEnabled: Bool)
            case setRainAutomation(zip: String, threshold: Int, isEnabled: Bool)
        }

        let id = UUID()
        let kind: Kind
        let enqueuedAt: Date

        init(kind: Kind, enqueuedAt: Date = Date()) {
            self.kind = kind
            self.enqueuedAt = enqueuedAt
        }

        var coalescingKey: String? {
            switch kind {
            case .setPin(let pin, _, _, _), .timedPinRun(let pin, _, _), .updatePin(let pin, _, _, _):
                return "pin-\(pin)"
            case .reorderPins:
                return "pin-reorder"
            case .setRain:
                return "rain-state"
            case .updateRainSettings:
                return "rain-settings"
            case .setRainAutomation:
                return "rain-automation"
            }
        }

        func isExpired(relativeTo referenceDate: Date, timeout: TimeInterval) -> Bool {
            guard case .timedPinRun = kind else { return false }
            return referenceDate.timeIntervalSince(enqueuedAt) > timeout
        }
    }

    private struct RecentPinToggle {
        let desiredState: Bool
        let timestamp: Date
    }
    private lazy var bonjourDiscovery: BonjourServiceDiscovery = {
        BonjourServiceDiscovery(
            serviceType: "_sprinkler._tcp.",
            domain: "local.",
            updateHandler: { [weak self] services in
                Task { @MainActor in
                    self?.discoveredServices = services
                }
            },
            stateHandler: { [weak self] isSearching in
                Task { @MainActor in
                    self?.isDiscoveringServices = isSearching
                }
            }
        )
    }()

    private let targetKey = "sprinkler.target_address"
    private let keychainTargetKey = "sprinkler.target_address_secure"
    private let lastSuccessKey = "sprinkler.last_success"
    private let versionKey = "sprinkler.server_version"
    private let manualRainDelayKey = "sprinkler.manual_rain_delay_hours"
    private let timedRunQueueExpiry: TimeInterval = 15 * 60
    private let offlineQueueNotice = "Controller is unreachable. Pending changes will sync automatically once reconnected."
    private let idlePollingInterval: TimeInterval = 20
    private let activePollingInterval: TimeInterval = 5
    private let offlinePollingInterval: TimeInterval = 30
    private let manualToggleDefaultDurationMinutes = 5
    private let pinToggleOverrideWindow: TimeInterval = 15
    private var statusPollingTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard,
         keychain: KeychainStoring = KeychainStorage(),
         client: APIClient = APIClient()) {
        self.defaults = userDefaults
        self.keychain = keychain
        self.client = client
        self.statusCache = StatusCache()
        self.schedulePersistence = SchedulePersistence()
        let persistedSchedules = schedulePersistence.load()
        self.schedules = persistedSchedules.schedules
        self.pendingScheduleDeletionIds = Set(persistedSchedules.pendingDeletionIds)
        self.pendingScheduleReorder = persistedSchedules.pendingReorder
        let storedManualDelay = userDefaults.integer(forKey: manualRainDelayKey)
        if storedManualDelay > 0 {
            self.manualRainDelayHours = storedManualDelay
        } else {
            self.manualRainDelayHours = 12
        }

        let keychainValue = keychain.string(forKey: keychainTargetKey)
        let defaultsValue = userDefaults.string(forKey: targetKey)

        if keychainValue == nil, let defaultsValue {
            try? keychain.set(defaultsValue, forKey: keychainTargetKey)
            userDefaults.removeObject(forKey: targetKey)
        }

        let savedAddress = keychainValue ?? defaultsValue ?? ""
        let trimmedSavedAddress = savedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedURL = try? Validators.normalizeBaseAddress(trimmedSavedAddress) {
            let canonicalAddress = normalizedURL.absoluteString
            self.targetAddress = canonicalAddress
            self.validationError = nil
            self.resolvedBaseURL = normalizedURL
            if !trimmedSavedAddress.isEmpty, canonicalAddress != trimmedSavedAddress {
                persistTargetAddress(normalizedURL)
            }
        } else {
            self.targetAddress = trimmedSavedAddress
            self.validationError = nil
            self.resolvedBaseURL = nil
        }
        self.lastSuccessfulConnection = userDefaults.object(forKey: lastSuccessKey) as? Date
        self.serverVersion = userDefaults.string(forKey: versionKey)

        if let cachedStatus = statusCache.load() {
            apply(status: cachedStatus)
        }

        if let baseURL = resolvedBaseURL {
            Task { await client.updateBaseURL(baseURL) }
            if let lastSuccessfulConnection {
                connectionStatus = .connected(lastSuccessfulConnection)
            }
        }

        updatePendingSyncMessage()
    }

    func refresh() async {
        await fetchStatus(source: .interactive)
    }

    func beginStatusPolling() {
        if let task = statusPollingTask, !task.isCancelled {
            return
        }
        statusPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.statusPollingLoop()
        }
    }

    func endStatusPolling() {
        statusPollingTask?.cancel()
        statusPollingTask = nil
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

    func beginBonjourDiscovery() {
        bonjourDiscovery.start()
    }

    func endBonjourDiscovery() {
        bonjourDiscovery.stop()
    }

    func useDiscoveredService(_ service: DiscoveredSprinklerService) {
        let url = service.baseURL
        if let normalized = try? Validators.normalizeBaseAddress(url.absoluteString) {
            let canonical = normalized.absoluteString
            if targetAddress != canonical {
                targetAddress = canonical
            }
            resolvedBaseURL = normalized
        } else {
            let absolute = url.absoluteString
            if targetAddress != absolute {
                targetAddress = absolute
            }
            resolvedBaseURL = nil
        }
        validationError = nil
    }

    private func fetchStatus(source: StatusRefreshSource) async {
        guard resolvedBaseURL != nil else { return }
        if source == .background, isRefreshing {
            return
        }

        if source == .interactive {
            isRefreshing = true
            connectionStatus = .connecting
        }

        let start = Date()
        defer {
            if source == .interactive {
                isRefreshing = false
            }
        }

        do {
            let status = try await client.fetchStatus()
            let now = Date()
            connectionDiagnostics = ConnectionDiagnostics(timestamp: now,
                                                          latency: now.timeIntervalSince(start))
            apply(status: status)
            statusCache.save(status)
            connectionStatus = .connected(now)
            recordConnectionSuccess(version: status.version)
        } catch let apiError as APIError {
            handleStatusFetchFailure(apiError, source: source)
        } catch {
            handleStatusFetchFailure(.invalidResponse, source: source)
        }
    }

    private func handleStatusFetchFailure(_ error: APIError, source: StatusRefreshSource) {
        connectionStatus = .unreachable(error.localizedDescription)
        recordConnectionFailure(error)
        if source == .interactive {
            showToast(message: error.localizedDescription, style: .error)
        }
    }

    private func statusPollingLoop() async {
        defer { statusPollingTask = nil }
        while !Task.isCancelled {
            if resolvedBaseURL != nil {
                await fetchStatus(source: .background)
            }

            let delay = max(2.0, nextPollingInterval())
            let nanoseconds = UInt64(delay * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                break
            }
        }
    }

    private func nextPollingInterval() -> TimeInterval {
        guard resolvedBaseURL != nil else { return 10 }
        if connectionStatus.isReachable {
            return runningPins.isEmpty ? idlePollingInterval : activePollingInterval
        }
        return offlinePollingInterval
    }

    func togglePin(_ pin: PinDTO, to desiredState: Bool) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let previousState = pins[index].isActive
        if previousState == desiredState { return }
        pins[index].isActive = desiredState

        let overrideMinutes = desiredState ? manualToggleDefaultDurationMinutes : nil
        let operation = PendingOperation(kind: .setPin(pin: pin.pin,
                                                       isOn: desiredState,
                                                       minutes: overrideMinutes,
                                                       displayName: pin.displayName))
        registerRecentToggle(pin: pin.pin, desiredState: desiredState)

        guard connectionStatus.isReachable else {
            enqueuePendingOperation(operation, notice: offlineQueueNotice)
            persistCurrentStateSnapshot()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.setPin(pin.pin, on: desiredState, minutes: overrideMinutes)
                await self.fetchStatus(source: .background)
            } catch let error as APIError {
                await MainActor.run {
                    if case .unreachable = error {
                        self.connectionStatus = .unreachable(error.localizedDescription)
                        self.recordConnectionFailure(error)
                        self.enqueuePendingOperation(operation, notice: self.offlineQueueNotice)
                        self.persistCurrentStateSnapshot()
                        self.recentPinToggles.removeValue(forKey: pin.pin)
                        return
                    }

                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex].isActive = previousState
                    }
                    self.recentPinToggles.removeValue(forKey: pin.pin)
                    self.connectionErrorMessage = error.localizedDescription
                    self.showToast(message: self.toastMessage(for: error, defaultMessage: "Failed to update pin"),
                                   style: .error)
                }
            } catch {
                await MainActor.run {
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex].isActive = previousState
                    }
                    self.recentPinToggles.removeValue(forKey: pin.pin)
                    self.connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    self.showToast(message: "Failed to update pin", style: .error)
                }
            }
        }
    }

    func runPin(_ pin: PinDTO, forMinutes minutes: Int) {
        let sanitizedMinutes = max(0, minutes)
        guard sanitizedMinutes > 0 else {
            showToast(message: "Enter a duration greater than zero.", style: .error)
            return
        }
        guard sanitizedMinutes <= 12 * 60 else {
            showToast(message: "Duration is too long.", style: .error)
            return
        }
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        if pins[index].isActive ?? false {
            showToast(message: "\(pin.displayName) is already running.", style: .error)
            return
        }

        let previouslyActive = pins[index].isActive ?? false
        pins[index].isActive = true

        let operation = PendingOperation(kind: .timedPinRun(pin: pin.pin,
                                                            durationMinutes: sanitizedMinutes,
                                                            displayName: pin.displayName))

        let offlineMessage = "\(pin.displayName) will start once the controller reconnects."

        guard connectionStatus.isReachable else {
            pins[index].isActive = previouslyActive
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: offlineMessage, style: .info)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.setPin(pin.pin, on: true, minutes: sanitizedMinutes)
                await self.refresh()
                await MainActor.run {
                    self.showToast(message: "Started \(pin.displayName) for \(sanitizedMinutes) minutes", style: .success)
                }
            } catch let error as APIError {
                await MainActor.run {
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex].isActive = previouslyActive
                    }
                    if case .unreachable = error {
                        self.connectionStatus = .unreachable(error.localizedDescription)
                        self.recordConnectionFailure(error)
                        self.enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        self.showToast(message: offlineMessage, style: .info)
                    } else {
                        self.connectionErrorMessage = error.localizedDescription
                        self.showToast(message: self.toastMessage(for: error,
                                                                   defaultMessage: "Failed to start \(pin.displayName)"),
                                       style: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex].isActive = previouslyActive
                    }
                    self.connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    self.showToast(message: "Failed to start \(pin.displayName)", style: .error)
                }
            }
        }
    }

    private func registerRecentToggle(pin: Int, desiredState: Bool) {
        purgeExpiredRecentToggles()
        recentPinToggles[pin] = RecentPinToggle(desiredState: desiredState, timestamp: Date())
    }

    private func purgeExpiredRecentToggles(referenceDate: Date = Date()) {
        let cutoff = referenceDate.addingTimeInterval(-pinToggleOverrideWindow)
        recentPinToggles = recentPinToggles.filter { _, value in value.timestamp >= cutoff }
    }

    func renamePin(_ pin: PinDTO, newName: String) {
        let normalizedNewName = normalizedName(from: newName)

        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }

        let currentNormalized = normalizedName(from: pins[index].name)
        guard currentNormalized != normalizedNewName else { return }

        let previousPin = pins[index]
        pins[index].name = normalizedNewName
        let isEnabled = pins[index].isEnabled ?? pin.isEnabled ?? true

        let operation = PendingOperation(kind: .updatePin(pin: pin.pin,
                                                          name: normalizedNewName,
                                                          isEnabled: isEnabled,
                                                          displayName: pin.displayName))

        guard connectionStatus.isReachable else {
            persistCurrentStateSnapshot()
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: "Rename saved. Will sync when connected.", style: .info)
            return
        }

        Task {
            do {
                try await client.updatePin(pin.pin, name: normalizedNewName, isEnabled: isEnabled)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.persistCurrentStateSnapshot()
                    self.showToast(message: "Pin renamed", style: .success)
                }
            } catch let error as APIError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if case .unreachable = error {
                        self.connectionStatus = .unreachable(error.localizedDescription)
                        self.recordConnectionFailure(error)
                        self.persistCurrentStateSnapshot()
                        self.enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        self.showToast(message: "Rename saved. Will sync when connected.", style: .info)
                        return
                    }

                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previousPin
                    }
                    self.connectionErrorMessage = error.localizedDescription
                    self.showToast(message: self.toastMessage(for: error, defaultMessage: "Rename failed"),
                                   style: .error)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previousPin
                    }
                    self.connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    self.showToast(message: self.toastMessage(for: error, defaultMessage: "Rename failed"),
                                   style: .error)
                }
            }
        }
    }

    func setPinEnabled(_ pin: PinDTO, isEnabled: Bool) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        let previous = pins[index]
        pins[index].isEnabled = isEnabled

        let normalizedName = normalizedName(from: pins[index].name)
        let operation = PendingOperation(kind: .updatePin(pin: pin.pin,
                                                          name: normalizedName,
                                                          isEnabled: isEnabled,
                                                          displayName: pin.displayName))

        guard connectionStatus.isReachable else {
            persistCurrentStateSnapshot()
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: "Pin update saved. Will sync when connected.", style: .info)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.updatePin(pin.pin, name: normalizedName, isEnabled: isEnabled)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.persistCurrentStateSnapshot()
                    self.showToast(message: isEnabled ? "Pin enabled" : "Pin hidden", style: .success)
                }
            } catch let error as APIError {
                await MainActor.run {
                    if case .unreachable = error {
                        self.connectionStatus = .unreachable(error.localizedDescription)
                        self.recordConnectionFailure(error)
                        self.persistCurrentStateSnapshot()
                        self.enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        self.showToast(message: "Pin update saved. Will sync when connected.", style: .info)
                        return
                    }

                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previous
                    }
                    self.connectionErrorMessage = error.localizedDescription
                    self.showToast(message: "Failed to update pin", style: .error)
                }
            } catch {
                await MainActor.run {
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previous
                    }
                    self.connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    self.showToast(message: "Failed to update pin", style: .error)
                }
            }
        }
    }

    func setRain(active: Bool, durationHours: Int?) {
        let operation = PendingOperation(kind: .setRain(isActive: active, durationHours: durationHours))
        let offlineMessage = active ? "Rain delay will activate when the controller reconnects." : "Rain delay change will sync when connected."

        guard connectionStatus.isReachable else {
            if let durationHours, durationHours > 0 {
                updateManualRainDelayHours(durationHours)
            }
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: offlineMessage, style: .info)
            return
        }

        Task {
            do {
                try await client.setRain(isActive: active, durationHours: durationHours)
                await refresh()
                await MainActor.run {
                    showToast(message: "Rain delay updated", style: .success)
                    if let durationHours, durationHours > 0 {
                        updateManualRainDelayHours(durationHours)
                    }
                }
            } catch let error as APIError {
                await MainActor.run {
                    if case .unreachable = error {
                        if let durationHours, durationHours > 0 {
                            updateManualRainDelayHours(durationHours)
                        }
                        connectionStatus = .unreachable(error.localizedDescription)
                        recordConnectionFailure(error)
                        enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        showToast(message: offlineMessage, style: .info)
                        return
                    }

                    connectionErrorMessage = error.localizedDescription
                    showToast(message: toastMessage(for: error, defaultMessage: "Failed to update rain delay"), style: .error)
                }
            } catch {
                await MainActor.run {
                    connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    showToast(message: "Failed to update rain delay", style: .error)
                }
            }
        }
    }

    func updateManualRainDelayHours(_ hours: Int) {
        // Clamp to a reasonable range so accidental large values do not linger.
        let clamped = max(1, min(hours, 72))
        if manualRainDelayHours == clamped { return }
        manualRainDelayHours = clamped
        defaults.set(clamped, forKey: manualRainDelayKey)
    }

    func setRainAutomationEnabled(_ isEnabled: Bool) {
        guard let zipCode = resolvedAutomationZip(),
              let threshold = resolvedAutomationThreshold() else {
            showToast(message: "Configure rain settings first", style: .error)
            return
        }

        let previousValue = rainAutomationEnabled
        rainAutomationEnabled = isEnabled
        rainSettingsIsEnabled = isEnabled
        isUpdatingRainAutomation = true

        let operation = PendingOperation(kind: .setRainAutomation(zip: zipCode,
                                                                   threshold: threshold,
                                                                   isEnabled: isEnabled))

        guard connectionStatus.isReachable else {
            isUpdatingRainAutomation = false
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: isEnabled ? "Automation will enable once connected." : "Automation will disable once connected.",
                      style: .info)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.updateRainSettings(zipCode: zipCode,
                                                        thresholdPercent: threshold,
                                                        isEnabled: isEnabled)
                await self.refresh()
                await MainActor.run {
                    self.showToast(message: isEnabled ? "Rain delay automation enabled" : "Rain delay automation disabled",
                                   style: .success)
                }
            } catch let error as APIError {
                await MainActor.run {
                    if case .unreachable = error {
                        self.connectionStatus = .unreachable(error.localizedDescription)
                        self.recordConnectionFailure(error)
                        self.rainAutomationEnabled = isEnabled
                        self.rainSettingsIsEnabled = isEnabled
                        self.enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        self.showToast(message: isEnabled ? "Automation will enable once connected." : "Automation will disable once connected.",
                                       style: .info)
                    } else {
                        self.rainAutomationEnabled = previousValue
                        self.rainSettingsIsEnabled = previousValue
                        self.connectionErrorMessage = error.localizedDescription
                        self.showToast(message: self.toastMessage(for: error,
                                                                   defaultMessage: "Failed to update automation"),
                                       style: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    self.rainAutomationEnabled = previousValue
                    self.rainSettingsIsEnabled = previousValue
                    self.connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    self.showToast(message: self.toastMessage(for: error,
                                                               defaultMessage: "Failed to update automation"),
                                   style: .error)
                }
            }
            await MainActor.run {
                self.isUpdatingRainAutomation = false
            }
        }
    }

    func saveRainSettings() async {
        rainSettingsSaveTask?.cancel()
        rainSettingsSaveTask = nil
        await pushRainSettingsIfValid(showSuccessToast: true)
    }

    func updateRainSettings(zip: String? = nil, threshold: String? = nil) {
        if let zip { rainSettingsZip = zip }
        if let threshold { rainSettingsThreshold = threshold }

        rainSettingsSaveTask?.cancel()
        rainSettingsSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.pushRainSettingsIfValid(showSuccessToast: false)
        }
    }

    private func pushRainSettingsIfValid(showSuccessToast: Bool) async {
        let trimmedZip = rainSettingsZip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedZip = normalizeZipCode(trimmedZip) else {
            if showSuccessToast {
                showToast(message: "Enter a valid ZIP code", style: .error)
            }
            return
        }

        guard let threshold = parseThresholdPercent(rainSettingsThreshold) else {
            if showSuccessToast {
                showToast(message: "Threshold must be between 0 and 100", style: .error)
            }
            return
        }

        rainSettingsZip = normalizedZip
        rainSettingsThreshold = String(threshold)
        rainSettingsSaveTask = nil
        await pushRainSettings(zip: normalizedZip,
                               threshold: threshold,
                               isEnabled: rainSettingsIsEnabled,
                               showSuccessToast: showSuccessToast)
    }

    private func pushRainSettings(zip: String,
                                  threshold: Int,
                                  isEnabled: Bool,
                                  showSuccessToast: Bool) async {
        isSavingRainSettings = true
        defer { isSavingRainSettings = false }

        let operation = PendingOperation(kind: .updateRainSettings(zip: zip,
                                                                    threshold: threshold,
                                                                    isEnabled: isEnabled))
        let offlineMessage = "Rain settings saved locally. They will sync when the controller reconnects."

        guard connectionStatus.isReachable else {
            rainAutomationEnabled = isEnabled
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            showToast(message: offlineMessage, style: .info)
            return
        }

        do {
            try await client.updateRainSettings(zipCode: zip,
                                                thresholdPercent: threshold,
                                                isEnabled: isEnabled)
            rainAutomationEnabled = isEnabled
            await refresh()
            if showSuccessToast {
                showToast(message: "Rain settings saved", style: .success)
            }
        } catch let error as APIError {
            if case .unreachable = error {
                rainAutomationEnabled = isEnabled
                connectionStatus = .unreachable(error.localizedDescription)
                recordConnectionFailure(error)
                enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                showToast(message: offlineMessage, style: .info)
                return
            }

            connectionErrorMessage = error.localizedDescription
            showToast(message: toastMessage(for: error, defaultMessage: "Failed to save rain settings"),
                      style: .error)
        } catch {
            connectionErrorMessage = APIError.invalidResponse.localizedDescription
            showToast(message: toastMessage(for: error, defaultMessage: "Failed to save rain settings"),
                      style: .error)
        }
    }

    func upsertSchedule(_ draft: ScheduleDraft) {
        var schedule = draft.schedule
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedule.lastSyncedAt = schedules[index].lastSyncedAt
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        pendingScheduleDeletionIds.remove(schedule.id)
        persistSchedulesState()

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.syncSchedulesWithController()
            await MainActor.run {
                self.showScheduleSyncToast(outcome: outcome,
                                            successMessage: "Schedule saved",
                                            offlineMessage: "Schedule saved locally. Will sync when connected.",
                                            failureMessage: "Failed to save schedule")
            }
        }
    }

    func deleteSchedule(_ schedule: Schedule) {
        schedules.removeAll { $0.id == schedule.id }
        if schedule.lastSyncedAt != nil {
            pendingScheduleDeletionIds.insert(schedule.id)
        }
        persistSchedulesState()

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.syncSchedulesWithController()
            await MainActor.run {
                self.showScheduleSyncToast(outcome: outcome,
                                            successMessage: "Schedule deleted",
                                            offlineMessage: "Schedule removed locally. Will delete when connected.",
                                            failureMessage: "Unable to delete schedule")
            }
        }
    }

    func duplicateSchedule(_ schedule: Schedule) {
        var copy = schedule
        let baseName = normalizedName(from: schedule.name) ?? "Schedule"
        let duplicateName = baseName.isEmpty ? "Schedule Copy" : "\(baseName) Copy"
        copy.id = UUID().uuidString
        copy.name = duplicateName
        copy.lastModified = Date()
        copy.lastSyncedAt = nil
        schedules.append(copy)
        persistSchedulesState()

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.syncSchedulesWithController()
            await MainActor.run {
                self.showScheduleSyncToast(outcome: outcome,
                                            successMessage: "Schedule duplicated",
                                            offlineMessage: "Schedule copy saved locally. Will sync when connected.",
                                            failureMessage: "Failed to duplicate schedule")
            }
        }
    }

    func reorderSchedules(from offsets: IndexSet, to destination: Int) {
        var reordered = schedules
        reordered.move(fromOffsets: offsets, toOffset: destination)
        schedules = reordered
        pendingScheduleReorder = reordered.map { $0.id }
        persistSchedulesState()

        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.syncSchedulesWithController()
            await MainActor.run {
                self.showScheduleSyncToast(outcome: outcome,
                                            successMessage: "Schedule order updated",
                                            offlineMessage: "Schedule order saved locally. Will sync when connected.",
                                            failureMessage: "Failed to reorder schedules")
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
        let operation = PendingOperation(kind: .reorderPins(order: combined.map { $0.pin }))

        guard connectionStatus.isReachable else {
            enqueuePendingOperation(operation, notice: nil, forceNotice: true)
            persistCurrentStateSnapshot()
            showToast(message: "Pin order saved locally. Will sync when connected.", style: .info)
            return
        }

        Task {
            do {
                let order = combined.map { $0.pin }
                try await client.reorderPins(order)
            } catch let error as APIError {
                await MainActor.run {
                    if case .unreachable = error {
                        connectionStatus = .unreachable(error.localizedDescription)
                        recordConnectionFailure(error)
                        enqueuePendingOperation(operation, notice: nil, forceNotice: true)
                        persistCurrentStateSnapshot()
                        showToast(message: "Pin order saved locally. Will sync when connected.", style: .info)
                    } else {
                        connectionErrorMessage = error.localizedDescription
                        showToast(message: "Failed to reorder pins", style: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    connectionErrorMessage = APIError.invalidResponse.localizedDescription
                    showToast(message: "Failed to reorder pins", style: .error)
                }
            }
        }
    }

    func resolveCurrentAddress() throws -> URL {
        let url = try Validators.normalizeBaseAddress(targetAddress)
        validationError = nil
        let canonicalAddress = url.absoluteString
        if targetAddress != canonicalAddress {
            targetAddress = canonicalAddress
        }
        if resolvedBaseURL != url {
            resolvedBaseURL = url
        }
        persistTargetAddress(url)
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
        connectionErrorMessage = nil
        updatePendingSyncMessage()
        Task { await flushPendingOperations() }
    }

    func recordConnectionFailure(_ error: APIError) {
        lastFailure = error
        connectionDiagnostics = nil
        connectionErrorMessage = error.localizedDescription
        updatePendingSyncMessage()
    }

    func dismissErrorMessage() {
        connectionErrorMessage = nil
    }

    private func persistTargetAddress(_ url: URL) {
        let canonicalAddress = url.absoluteString
        if keychain.string(forKey: keychainTargetKey) == canonicalAddress {
            return
        }

        do {
            try keychain.set(canonicalAddress, forKey: keychainTargetKey)
            defaults.removeObject(forKey: targetKey)
        } catch {
            defaults.set(canonicalAddress, forKey: targetKey)
        }
    }

    private func apply(status: StatusDTO) {
        purgeExpiredRecentToggles(referenceDate: status.lastUpdated ?? Date())
        var mergedPins = PinCatalogMerger.merge(current: pins, remote: status.pins)
        if !recentPinToggles.isEmpty {
            var overrides = recentPinToggles
            mergedPins = mergedPins.map { pin in
                guard let override = overrides[pin.pin] else { return pin }
                if pin.isActive == override.desiredState {
                    overrides.removeValue(forKey: pin.pin)
                    return pin
                }
                var adjusted = pin
                adjusted.isActive = override.desiredState
                return adjusted
            }
            recentPinToggles = overrides
        }
        assignIfDifferent(\SprinklerStore.pins, to: mergedPins)
        let remoteSchedules = (status.schedules ?? []).map { Schedule(dto: $0, defaultPins: mergedPins) }
        mergeSchedulesWithRemote(remoteSchedules)
        assignIfDifferent(\SprinklerStore.rain, to: status.rain)
        syncRainSettings(from: status.rain)
        if let duration = status.rain?.durationHours, duration > 0 {
            updateManualRainDelayHours(duration)
        }
        updatePendingSyncMessage()
    }

    private func mergeSchedulesWithRemote(_ remoteSchedules: [Schedule]) {
        let now = Date()
        var merged: [String: Schedule] = [:]
        var localById = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })

        for remote in remoteSchedules {
            var normalized = remote
            normalized.lastModified = now
            normalized.lastSyncedAt = now
            if let local = localById.removeValue(forKey: remote.id) {
                if local.needsSync {
                    merged[local.id] = local
                    continue
                }
            }
            if !pendingScheduleDeletionIds.contains(normalized.id) {
                merged[normalized.id] = normalized
            }
        }

        for remaining in localById.values {
            if pendingScheduleDeletionIds.contains(remaining.id) {
                continue
            }
            merged[remaining.id] = remaining
        }

        for deletion in pendingScheduleDeletionIds {
            merged.removeValue(forKey: deletion)
        }

        let preferredOrder: [String]
        if let pendingOrder = pendingScheduleReorder, !pendingOrder.isEmpty {
            preferredOrder = pendingOrder
        } else {
            preferredOrder = remoteSchedules.map(\.id)
        }

        var ordered: [Schedule] = []
        var consumed: Set<String> = []
        for identifier in preferredOrder {
            guard let schedule = merged[identifier], !consumed.contains(identifier) else { continue }
            ordered.append(schedule)
            consumed.insert(identifier)
        }

        if ordered.count != merged.count {
            let remaining = merged.values.filter { !consumed.contains($0.id) }
            let sorted = remaining.sorted { lhs, rhs in
                if lhs.lastModified == rhs.lastModified {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.lastModified > rhs.lastModified
            }
            ordered.append(contentsOf: sorted)
        }

        if schedules != ordered {
            schedules = ordered
            persistSchedulesState()
        } else {
            persistSchedulesState()
        }
    }

    private func syncSchedulesWithController() async -> ScheduleSyncOutcome {
        guard connectionStatus.isReachable else { return .deferred }

        var encounteredError: Error?

        if let pendingOrder = pendingScheduleReorder {
            do {
                try await client.reorderSchedules(pendingOrder)
                pendingScheduleReorder = nil
            } catch {
                encounteredError = encounteredError ?? error
            }
        }

        if !pendingScheduleDeletionIds.isEmpty {
            let deletions = pendingScheduleDeletionIds
            for identifier in deletions {
                do {
                    try await client.deleteSchedule(id: identifier)
                    pendingScheduleDeletionIds.remove(identifier)
                } catch {
                    encounteredError = encounteredError ?? error
                }
            }
        }

        for index in schedules.indices {
            var schedule = schedules[index]
            guard schedule.needsSync else { continue }
            do {
                let payload = schedule.writePayload()
                if schedule.lastSyncedAt == nil {
                    try await client.createSchedule(payload)
                } else {
                    try await client.updateSchedule(id: schedule.id, schedule: payload)
                }
                let syncDate = Date()
                schedule.lastSyncedAt = syncDate
                schedule.lastModified = syncDate
                schedules[index] = schedule
            } catch {
                encounteredError = encounteredError ?? error
            }
        }

        persistSchedulesState()

        if let encounteredError {
            return .failed(encounteredError)
        }
        return .synced
    }

    private func showScheduleSyncToast(outcome: ScheduleSyncOutcome,
                                        successMessage: String,
                                        offlineMessage: String,
                                        failureMessage: String) {
        switch outcome {
        case .synced:
            showToast(message: successMessage, style: .success)
        case .deferred:
            showToast(message: offlineMessage, style: .info)
        case .failed(let error):
            showToast(message: toastMessage(for: error, defaultMessage: failureMessage), style: .error)
        }
    }

    private func normalizedName(from name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedName(from name: String?) -> String? {
        guard let name else { return nil }
        return normalizedName(from: name)
    }

    private func syncRainSettings(from rain: RainDTO?) {
        let newZip = rain?.zipCode ?? ""
        if rainSettingsZip != newZip {
            rainSettingsZip = newZip
        }

        let newThreshold = rain?.thresholdPercent.map(String.init) ?? ""
        if rainSettingsThreshold != newThreshold {
            rainSettingsThreshold = newThreshold
        }

        let automationEnabled = rain?.automationEnabled ?? false
        if rainSettingsIsEnabled != automationEnabled {
            rainSettingsIsEnabled = automationEnabled
        }
        if rainAutomationEnabled != automationEnabled {
            rainAutomationEnabled = automationEnabled
        }
    }

    private func resolvedAutomationZip() -> String? {
        if let zip = rain?.zipCode, normalizeZipCode(zip) != nil {
            return normalizeZipCode(zip)
        }
        return normalizeZipCode(rainSettingsZip)
    }

    private func resolvedAutomationThreshold() -> Int? {
        if let threshold = rain?.thresholdPercent, (0...100).contains(threshold) {
            return threshold
        }
        return parseThresholdPercent(rainSettingsThreshold)
    }

    private func normalizeZipCode(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 5, trimmed.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        return trimmed
    }

    private func parseThresholdPercent(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let threshold = Int(trimmed), (0...100).contains(threshold) else {
            return nil
        }
        return threshold
    }

    private func toastMessage(for error: Error, defaultMessage: String) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        return defaultMessage
    }

    func scheduleTimeline(relativeTo date: Date, calendar: Calendar = Calendar.current) -> (current: ScheduleRun?, next: ScheduleRun?) {
        let occurrences = scheduleOccurrences(relativeTo: date, calendar: calendar)
        let current = occurrences.first { $0.contains(date) }
        let upcoming = occurrences.first { $0.startDate > date }
        return (current, upcoming)
    }

    func scheduleOccurrences(relativeTo date: Date, calendar: Calendar = Calendar.current) -> [ScheduleRun] {
        guard !schedules.isEmpty else { return [] }

        let startOfDay = calendar.startOfDay(for: date)
        var runs: [ScheduleRun] = []

        for schedule in schedules where schedule.isEnabled {
            guard let timeComponents = parseTimeComponents(from: schedule.startTime) else { continue }
            let durationMinutes = schedule.totalDurationMinutes
            let weekdays = resolvedWeekdays(for: schedule, calendar: calendar)

            for offset in -1...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard weekdays.contains(weekday),
                      let startDate = calendar.date(bySettingHour: timeComponents.hour,
                                                   minute: timeComponents.minute,
                                                   second: 0,
                                                   of: day) else { continue }
                let endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
                runs.append(ScheduleRun(schedule: schedule, startDate: startDate, endDate: endDate))
            }
        }

        return runs.sorted { $0.startDate < $1.startDate }
    }

    private func parseTimeComponents(from string: String) -> (hour: Int, minute: Int)? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    private func resolvedWeekdays(for schedule: Schedule, calendar: Calendar) -> [Int] {
        guard !schedule.days.isEmpty else {
            return Array(1...7)
        }

        var result: Set<Int> = []
        for day in schedule.days {
            if let value = weekdayIndex(for: day, calendar: calendar) {
                result.insert(value)
            }
        }

        if result.isEmpty {
            return Array(1...7)
        }
        return result.sorted()
    }

    private func weekdayIndex(for string: String, calendar: Calendar) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let symbolSets = [calendar.weekdaySymbols, calendar.shortWeekdaySymbols, calendar.veryShortWeekdaySymbols]
        for symbols in symbolSets {
            if let index = symbols.firstIndex(where: { $0.lowercased() == trimmed }) {
                return index + 1
            }
        }

        let englishFull = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let index = englishFull.firstIndex(of: trimmed) {
            return index + 1
        }

        let englishShort = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let index = englishShort.firstIndex(of: trimmed) {
            return index + 1
        }

        let englishMini = ["su", "mo", "tu", "we", "th", "fr", "sa"]
        if let index = englishMini.firstIndex(of: trimmed) {
            return index + 1
        }

        if let numeric = Int(trimmed), (1...7).contains(numeric) {
            return numeric
        }

        return nil
    }

    private func enqueuePendingOperation(_ operation: PendingOperation, notice: String? = nil, forceNotice: Bool = false) {
        let wasEmpty = pendingOperations.isEmpty
        if let key = operation.coalescingKey {
            pendingOperations.removeAll { $0.coalescingKey == key }
        }
        pendingOperations.append(operation)
        updatePendingSyncMessage()
        if (wasEmpty || forceNotice), let notice {
            showToast(message: notice, style: .info)
        }
    }

    private func updatePendingSyncMessage() {
        let totalPending = pendingOperations.count + pendingScheduleChangeCount()
        if totalPending == 0 {
            if pendingSyncMessage != nil {
                pendingSyncMessage = nil
            }
            return
        }

        let message: String
        if totalPending == 1 {
            message = "1 change will sync once the controller reconnects."
        } else {
            message = "\(totalPending) changes will sync once the controller reconnects."
        }

        if pendingSyncMessage != message {
            pendingSyncMessage = message
        }
    }

    private func pendingScheduleChangeCount() -> Int {
        var count = pendingScheduleDeletionIds.count
        if pendingScheduleReorder != nil {
            count += 1
        }
        count += schedules.filter { $0.needsSync }.count
        return count
    }

    private func flushPendingOperations() async {
        guard !isFlushingPendingOperations else { return }
        guard connectionStatus.isReachable else { return }
        guard !pendingOperations.isEmpty else {
            updatePendingSyncMessage()
            return
        }

        isFlushingPendingOperations = true
        var syncedCount = 0
        defer {
            isFlushingPendingOperations = false
            updatePendingSyncMessage()
            if syncedCount > 0 {
                showToast(message: syncedCount == 1 ? "1 queued change synced" : "\(syncedCount) queued changes synced", style: .success)
            }
        }

        while !pendingOperations.isEmpty {
            let operation = pendingOperations.removeFirst()
            if operation.isExpired(relativeTo: Date(), timeout: timedRunQueueExpiry) {
                continue
            }

            do {
                try await perform(operation)
                syncedCount += 1
            } catch let error as APIError {
                if case .unreachable = error {
                    pendingOperations.insert(operation, at: 0)
                    connectionErrorMessage = error.localizedDescription
                    return
                }

                connectionErrorMessage = error.localizedDescription
                showToast(message: toastMessage(for: error, defaultMessage: "Failed to sync pending change"), style: .error)
            } catch {
                connectionErrorMessage = APIError.invalidResponse.localizedDescription
                showToast(message: "Failed to sync pending change", style: .error)
            }
        }
    }

    private func perform(_ operation: PendingOperation) async throws {
        switch operation.kind {
        case .setPin(let pin, let isOn, let minutes, _):
            try await client.setPin(pin, on: isOn, minutes: minutes ?? (isOn ? manualToggleDefaultDurationMinutes : nil))
        case .timedPinRun(let pin, let durationMinutes, _):
            try await client.setPin(pin, on: true, minutes: durationMinutes)
        case .updatePin(let pin, let name, let isEnabled, _):
            try await client.updatePin(pin, name: name, isEnabled: isEnabled)
        case .reorderPins(let order):
            try await client.reorderPins(order)
        case .setRain(let isActive, let durationHours):
            try await client.setRain(isActive: isActive, durationHours: durationHours)
        case .updateRainSettings(let zip, let threshold, let isEnabled):
            try await client.updateRainSettings(zipCode: zip, thresholdPercent: threshold, isEnabled: isEnabled)
        case .setRainAutomation(let zip, let threshold, let isEnabled):
            try await client.updateRainSettings(zipCode: zip, thresholdPercent: threshold, isEnabled: isEnabled)
        }
    }

    /// Persists the latest in-memory status so future launches (and offline
    /// sessions) reflect configuration changes such as renames immediately.
    @MainActor
    private func persistSchedulesState() {
        let state = SchedulePersistenceState(schedules: schedules,
                                             pendingDeletionIds: Array(pendingScheduleDeletionIds),
                                             pendingReorder: pendingScheduleReorder)
        schedulePersistence.save(state)
        persistCurrentStateSnapshot()
        updatePendingSyncMessage()
    }

    private func persistCurrentStateSnapshot() {
        let snapshot = StatusDTO(pins: pins,
                                 schedules: schedules.map { $0.dto() },
                                 rain: rain,
                                 version: serverVersion,
                                 lastUpdated: Date())
        statusCache.save(snapshot)
    }

    private func showToast(message: String, style: ToastState.Style) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toast = ToastState(message: message, style: style)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.message == message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toast = nil
                }
            }
        }
    }

    private func assignIfDifferent<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SprinklerStore, Value>, to newValue: Value) {
        if self[keyPath: keyPath] != newValue {
            self[keyPath: keyPath] = newValue
        }
    }

    deinit {
        statusPollingTask?.cancel()
    }
}

// MARK: - Supporting Types

/// Represents a discovered sprinkler controller advertised via Bonjour/mDNS.
struct DiscoveredSprinklerService: Identifiable, Equatable {
    /// Stable identifier constructed from the service name and domain information.
    let identifier: String
    /// User-visible service name provided by Bonjour.
    let name: String
    /// Host component resolved for the service.
    let host: NWEndpoint.Host
    /// TCP port the service is listening on.
    let port: NWEndpoint.Port
    /// Potential base URLs for the controller, ordered by preference.
    let candidateURLs: [URL]
    /// IP addresses returned by the Bonjour resolution for diagnostics.
    let ipAddresses: [String]

    var id: String { identifier }

    /// Preferred base URL for the discovered controller.
    var baseURL: URL { candidateURLs[0] }

    /// Alternative URLs (e.g. hostname variants) for the controller.
    var alternativeURLs: [URL] { Array(candidateURLs.dropFirst()) }

    /// User-facing description of the resolved host/port combination.
    var detailDescription: String {
        let hostString: String
        if let firstIP = ipAddresses.first {
            hostString = firstIP
        } else {
            hostString = host.displayString
        }
        return "\(hostString):\(port.rawValue)"
    }
}

/// Discovers sprinkler controllers advertised over Bonjour and publishes updates.
final class BonjourServiceDiscovery: NSObject {
    typealias ServicesUpdateHandler = ([DiscoveredSprinklerService]) -> Void
    typealias StateChangeHandler = (Bool) -> Void

    private let serviceType: String
    private let domain: String
    private let updateHandler: ServicesUpdateHandler
    private let stateHandler: StateChangeHandler

    private let browser: NetServiceBrowser
    private var activeServices: [String: NetService] = [:]
    private var discovered: [String: DiscoveredSprinklerService] = [:]
    private var isSearching: Bool = false

    init(serviceType: String = "_sprinkler._tcp.",
         domain: String = "local.",
         updateHandler: @escaping ServicesUpdateHandler,
         stateHandler: @escaping StateChangeHandler) {
        self.serviceType = serviceType
        self.domain = domain
        self.updateHandler = updateHandler
        self.stateHandler = stateHandler
        self.browser = NetServiceBrowser()
        super.init()
        browser.delegate = self
        browser.includesPeerToPeer = true
    }

    /// Begins the Bonjour discovery process. Subsequent calls while discovery is running are ignored.
    func start() {
        guard !isSearching else { return }
        isSearching = true
        notifyStateChange(isSearching)
        browser.searchForServices(ofType: serviceType, inDomain: domain)
    }

    /// Stops the current Bonjour search and clears any cached results.
    func stop() {
        guard isSearching else { return }
        isSearching = false
        browser.stop()
        activeServices.removeAll()
        discovered.removeAll()
        notifyStateChange(isSearching)
        notifyUpdates()
    }

    private func identifier(for service: NetService) -> String {
        "\(service.name).\(service.domain)"
    }

    private func handleResolution(for service: NetService) {
        let identifier = identifier(for: service)
        guard let resolvedPort = NWEndpoint.Port(rawValue: UInt16(service.port)), resolvedPort.rawValue > 0 else { return }

        let rawHost: String
        if let hostName = service.hostName {
            rawHost = hostName
        } else {
            rawHost = "\(service.name).\(service.domain)"
        }
        let sanitizedHost = sanitizeHostName(rawHost)
        let endpointHost: NWEndpoint.Host
        if let ipv4 = IPv4Address(sanitizedHost) {
            endpointHost = .ipv4(ipv4)
        } else if let ipv6 = IPv6Address(sanitizedHost) {
            endpointHost = .ipv6(ipv6)
        } else {
            endpointHost = .name(sanitizedHost, nil)
        }

        var ipAddresses: [String] = []
        var ipSet: Set<String> = []
        var urlCandidates: [URL] = []
        var urlSet: Set<String> = []

        if let addresses = service.addresses {
            for addressData in addresses {
                guard let ipString = Self.ipAddress(from: addressData) else { continue }
                if !ipSet.contains(ipString) {
                    ipSet.insert(ipString)
                    ipAddresses.append(ipString)
                }
                if let url = Self.httpURL(fromHost: ipString, port: resolvedPort) {
                    let absolute = url.absoluteString
                    if !urlSet.contains(absolute) {
                        urlSet.insert(absolute)
                        urlCandidates.append(url)
                    }
                }
            }
        }

        if let hostURL = Self.httpURL(fromHost: endpointHost.displayString, port: resolvedPort) {
            let absolute = hostURL.absoluteString
            if !urlSet.contains(absolute) {
                urlSet.insert(absolute)
                urlCandidates.append(hostURL)
            }
        }

        guard !urlCandidates.isEmpty else { return }

        let serviceInfo = DiscoveredSprinklerService(identifier: identifier,
                                                     name: service.name,
                                                     host: endpointHost,
                                                     port: resolvedPort,
                                                     candidateURLs: urlCandidates,
                                                     ipAddresses: ipAddresses)
        discovered[identifier] = serviceInfo
        notifyUpdates()
    }

    private func sanitizeHostName(_ host: String) -> String {
        guard host.hasSuffix(".") else { return host }
        return String(host.dropLast())
    }

    private func notifyUpdates() {
        let services = discovered.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [services, handler = updateHandler] in
            handler(services)
        }
    }

    private func notifyStateChange(_ searching: Bool) {
        DispatchQueue.main.async { [handler = stateHandler] in
            handler(searching)
        }
    }

    private static func httpURL(fromHost host: String, port: NWEndpoint.Port) -> URL? {
        let requiresBrackets = host.contains(":") && !host.hasPrefix("[")
        let hostComponent = requiresBrackets ? "[\(host)]" : host
        if port.rawValue > 0 {
            return URL(string: "http://\(hostComponent):\(port.rawValue)")
        } else {
            return URL(string: "http://\(hostComponent)")
        }
    }

    private static func ipAddress(from data: Data) -> String? {
        return data.withUnsafeBytes { rawPointer -> String? in
            guard let baseAddress = rawPointer.baseAddress else { return nil }
            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)

            switch Int32(sockaddrPointer.pointee.sa_family) {
            case AF_INET:
                let ipv4Pointer = UnsafeRawPointer(sockaddrPointer).assumingMemoryBound(to: sockaddr_in.self)
                var address = ipv4Pointer.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            case AF_INET6:
                let ipv6Pointer = UnsafeRawPointer(sockaddrPointer).assumingMemoryBound(to: sockaddr_in6.self)
                var address = ipv6Pointer.pointee.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            default:
                return nil
            }
        }
    }
}

extension BonjourServiceDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        notifyStateChange(true)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
        notifyStateChange(false)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        isSearching = false
        notifyStateChange(false)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let identifier = identifier(for: service)
        activeServices[identifier] = service
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        if !moreComing {
            notifyUpdates()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let identifier = identifier(for: service)
        activeServices.removeValue(forKey: identifier)
        discovered.removeValue(forKey: identifier)
        if !moreComing {
            notifyUpdates()
        }
    }
}

extension BonjourServiceDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        handleResolution(for: sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        activeServices.removeValue(forKey: identifier(for: sender))
    }
}

private extension NWEndpoint.Host {
    var displayString: String {
        switch self {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return address.debugDescription
        case .ipv6(let address):
            return address.debugDescription
        @unknown default:
            return ""
        }
    }
}

/// Persists the last successfully fetched `StatusDTO` so the UI can bootstrap
/// with cached data while a fresh network request is pending.
final class StatusCache {
    private struct Snapshot: Codable {
        let cacheVersion: Int
        let savedAt: Date
        let status: StatusDTO
    }

    private enum Constants {
        static let cacheVersion = 1
        static let directoryName = "StatusCache"
        static let fileName = "snapshot.json"
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.sprinklermobile.status-cache")
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            for formatter in [fractionalFormatter, standardFormatter] {
                if let date = formatter.date(from: value) {
                    return date
                }
            }

            if let interval = TimeInterval(value) {
                return Date(timeIntervalSince1970: interval)
            }

            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognized date format: \(value)")
        }

        self.fileURL = StatusCache.makeFileURL(fileManager: fileManager)
    }

    func load() -> StatusDTO? {
        guard let fileURL else { return nil }

        return queue.sync {
            do {
                let data = try Data(contentsOf: fileURL)
                let snapshot = try decoder.decode(Snapshot.self, from: data)
                guard snapshot.cacheVersion == Constants.cacheVersion else {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }
                return snapshot.status
            } catch {
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }
    }

    func save(_ status: StatusDTO) {
        guard let fileURL else { return }

        queue.async {
            let snapshot = Snapshot(cacheVersion: Constants.cacheVersion,
                                    savedAt: Date(),
                                    status: status)
            do {
                let data = try self.encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                try? self.fileManager.removeItem(at: fileURL)
            }
        }
    }

    func clear() {
        guard let fileURL else { return }

        queue.async {
            try? self.fileManager.removeItem(at: fileURL)
        }
    }

    private static func makeFileURL(fileManager: FileManager) -> URL? {
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first else {
            return nil
        }

        let directory = baseDirectory.appendingPathComponent(Constants.directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(Constants.fileName, isDirectory: false)
        } catch {
            return nil
        }
    }
}

extension SprinklerStore {
    /// Test-only helper that seeds deterministic pins and schedules without hitting the network.
    func configureForTesting(pins: [PinDTO], schedules: [Schedule]) {
        self.pins = pins
        self.schedules = schedules
        pendingScheduleDeletionIds.removeAll()
        pendingScheduleReorder = nil
        persistSchedulesState()
    }
}
