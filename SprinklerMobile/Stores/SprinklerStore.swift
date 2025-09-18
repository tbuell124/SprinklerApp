import Foundation
import Combine
import Network
import Darwin

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

    // Remote resources
    @Published private(set) var pins: [PinDTO] = PinDTO.makeDefaultSprinklerPins()
    var activePins: [PinDTO] {
        pins.filter { $0.isEnabled ?? true }
    }
    @Published private(set) var schedules: [ScheduleDTO] = []
    @Published private(set) var scheduleGroups: [ScheduleGroupDTO] = []
    @Published private(set) var rain: RainDTO?
    @Published private(set) var rainAutomationEnabled: Bool = false
    @Published var rainSettingsZip: String = ""
    @Published var rainSettingsThreshold: String = ""
    @Published var rainSettingsIsEnabled: Bool = false
    @Published var isSavingRainSettings: Bool = false
    @Published var isUpdatingRainAutomation: Bool = false

    // Connection state
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var isRefreshing: Bool = false
    @Published var toast: ToastState?
    @Published private(set) var connectionDiagnostics: ConnectionDiagnostics?

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

    init(userDefaults: UserDefaults = .standard,
         keychain: KeychainStoring = KeychainStorage(),
         client: APIClient = APIClient()) {
        self.defaults = userDefaults
        self.keychain = keychain
        self.client = client
        self.statusCache = StatusCache()

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
    }

    func refresh() async {
        guard resolvedBaseURL != nil else { return }
        isRefreshing = true
        connectionStatus = .connecting
        defer { isRefreshing = false }
        do {
            let start = Date()
            let status = try await client.fetchStatus()
            let now = Date()
            connectionDiagnostics = ConnectionDiagnostics(timestamp: now,
                                                          latency: now.timeIntervalSince(start))
            apply(status: status)
            statusCache.save(status)
            connectionStatus = .connected(now)
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
        let normalizedNewName = normalizedName(from: newName)

        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }

        let currentNormalized = normalizedName(from: pins[index].name)
        guard currentNormalized != normalizedNewName else { return }

        let previousPin = pins[index]
        pins[index].name = normalizedNewName
        let isEnabled = pins[index].isEnabled ?? pin.isEnabled ?? true

        Task {
            do {
                try await client.updatePin(pin.pin, name: normalizedNewName, isEnabled: isEnabled)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.persistCurrentStateSnapshot()
                    self.showToast(message: "Pin renamed", style: .success)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previousPin
                    }
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
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.updatePin(pin.pin, name: normalizedName, isEnabled: isEnabled)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.persistCurrentStateSnapshot()
                    self.showToast(message: isEnabled ? "Pin enabled" : "Pin hidden", style: .success)
                }
            } catch {
                await MainActor.run {
                    if let revertIndex = self.pins.firstIndex(where: { $0.id == pin.id }) {
                        self.pins[revertIndex] = previous
                    }
                    self.showToast(message: "Failed to update pin", style: .error)
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
            } catch {
                await MainActor.run {
                    self.rainAutomationEnabled = previousValue
                    self.rainSettingsIsEnabled = previousValue
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
        let trimmedZip = rainSettingsZip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedZip = normalizeZipCode(trimmedZip) else {
            showToast(message: "Enter a valid ZIP code", style: .error)
            return
        }

        guard let threshold = parseThresholdPercent(rainSettingsThreshold) else {
            showToast(message: "Threshold must be between 0 and 100", style: .error)
            return
        }

        rainSettingsZip = normalizedZip
        rainSettingsThreshold = String(threshold)
        isSavingRainSettings = true
        defer { isSavingRainSettings = false }

        do {
            try await client.updateRainSettings(zipCode: normalizedZip,
                                                thresholdPercent: threshold,
                                                isEnabled: rainSettingsIsEnabled)
            rainAutomationEnabled = rainSettingsIsEnabled
            await refresh()
            showToast(message: "Rain settings saved", style: .success)
        } catch {
            showToast(message: toastMessage(for: error, defaultMessage: "Failed to save rain settings"),
                      style: .error)
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
    }

    func recordConnectionFailure(_ error: APIError) {
        lastFailure = error
        connectionDiagnostics = nil
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
        let mergedPins = mergePinsWithCatalog(status.pins ?? [])
        assignIfDifferent(\SprinklerStore.pins, to: mergedPins)
        assignIfDifferent(\SprinklerStore.schedules, to: status.schedules ?? [])
        assignIfDifferent(\SprinklerStore.scheduleGroups, to: status.scheduleGroups ?? [])
        assignIfDifferent(\SprinklerStore.rain, to: status.rain)
        syncRainSettings(from: status.rain)
    }

    /// Blends controller supplied pin metadata with the static catalog so every
    /// safely drivable GPIO appears in the UI even if the backend omits it.
    private func mergePinsWithCatalog(_ remotePins: [PinDTO]) -> [PinDTO] {
        let catalog = PinDTO.sprinklerSafeOutputPins
        let catalogSet = Set(catalog)

        var catalogOverrides: [Int: PinDTO] = [:]
        var additionalPins: [PinDTO] = []

        for pin in remotePins {
            if catalogSet.contains(pin.pin) {
                // Preserve the backend-provided configuration for catalog pins.
                catalogOverrides[pin.pin] = pin
            } else {
                // Keep any extra pins returned by the server so nothing is lost.
                additionalPins.append(pin)
            }
        }

        let catalogPins = catalog.map { pinNumber -> PinDTO in
            if let existing = catalogOverrides[pinNumber] {
                return existing
            }
            // Backend did not report this pin, so surface it as a disabled placeholder.
            return PinDTO(pin: pinNumber,
                          name: nil,
                          isActive: nil,
                          isEnabled: false)
        }

        // Append any non-catalog pins so the full server response remains visible.
        let sortedAdditionalPins = additionalPins.sorted { $0.pin < $1.pin }
        return catalogPins + sortedAdditionalPins
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

    /// Persists the latest in-memory status so future launches (and offline
    /// sessions) reflect configuration changes such as renames immediately.
    @MainActor
    private func persistCurrentStateSnapshot() {
        let snapshot = StatusDTO(pins: pins,
                                 schedules: schedules,
                                 scheduleGroups: scheduleGroups,
                                 rain: rain,
                                 version: serverVersion,
                                 lastUpdated: Date())
        statusCache.save(snapshot)
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
