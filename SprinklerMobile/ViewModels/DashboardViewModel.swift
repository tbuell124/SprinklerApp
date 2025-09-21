import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var state: DashboardState = .loading
    @Published var currentlyRunning: RunningSchedule?
    @Published var upNext: UpcomingSchedule?
    @Published var rainDelayUntil: Date?
    @Published var lastSeenTime: Date?
    
    private var sprinklerStore: SprinklerStore
    private var connectivityStore: ConnectivityStore
    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?
    
    init(sprinklerStore: SprinklerStore, connectivityStore: ConnectivityStore) {
        self.sprinklerStore = sprinklerStore
        self.connectivityStore = connectivityStore
        setupBindings()
        startCountdownTimer()
    }
    
    deinit {
        countdownTimer?.invalidate()
    }
    
    func updateStores(sprinklerStore: SprinklerStore, connectivityStore: ConnectivityStore) {
        cancellables.removeAll()
        countdownTimer?.invalidate()
        
        self.sprinklerStore = sprinklerStore
        self.connectivityStore = connectivityStore
        
        setupBindings()
        startCountdownTimer()
    }
    
    private func setupBindings() {
        Publishers.CombineLatest3(
            sprinklerStore.$isRefreshing,
            sprinklerStore.$connectionErrorMessage,
            connectivityStore.$state
        )
        .map { isRefreshing, errorMessage, connectivityState in
            if isRefreshing {
                return DashboardState.loading
            } else if let error = errorMessage, !error.isEmpty {
                return DashboardState.error(error) { [weak self] in
                    Task { @MainActor in
                        await self?.retry()
                    }
                }
            } else {
                return DashboardState.ready
            }
        }
        .receive(on: DispatchQueue.main)
        .assign(to: &$state)
        
        sprinklerStore.$pins
            .combineLatest(sprinklerStore.$schedules)
            .map { [weak self] pins, schedules in
                self?.updateRunningAndUpcoming(pins: pins, schedules: schedules)
            }
            .receive(on: DispatchQueue.main)
            .sink { _ in }
            .store(in: &cancellables)
        
        sprinklerStore.$rain
            .map { $0?.delayUntil }
            .receive(on: DispatchQueue.main)
            .assign(to: &$rainDelayUntil)
            .store(in: &cancellables)
        
        connectivityStore.$lastSuccessfulCheck
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastSeenTime)
            .store(in: &cancellables)
    }
    
    private func updateRunningAndUpcoming(pins: [PinDTO], schedules: [Schedule]) {
        let runningPin = pins.first { ($0.isActive ?? false) }
        
        if let pin = runningPin {
            currentlyRunning = RunningSchedule(
                name: pin.displayName,
                zone: "Zone \(pin.pin)",
                remainingSeconds: 600
            )
        } else {
            currentlyRunning = nil
        }
        
        let now = Date()
        let upcomingSchedule = schedules
            .filter { $0.isEnabled }
            .compactMap { schedule -> (Schedule, Date)? in
                guard let nextRun = schedule.nextRunDate(after: now) else { return nil }
                return (schedule, nextRun)
            }
            .min { $0.1 < $1.1 }
        
        if let (schedule, nextRun) = upcomingSchedule {
            upNext = UpcomingSchedule(
                name: schedule.name,
                eta: nextRun
            )
        } else {
            upNext = nil
        }
    }
    
    private func startCountdownTimer() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }
    
    private func updateCountdown() {
        guard let running = currentlyRunning, running.remainingSeconds > 0 else {
            currentlyRunning = nil
            return
        }
        
        currentlyRunning = RunningSchedule(
            name: running.name,
            zone: running.zone,
            remainingSeconds: max(0, running.remainingSeconds - 1)
        )
    }
    
    private func retry() async {
        await sprinklerStore.refresh()
    }
    
    func togglePin(_ pin: PinDTO, duration: Int = 10) async {
        await sprinklerStore.runPin(pin, forMinutes: duration)
    }
    
    func disableRainDelay() async {
        await sprinklerStore.setRain(active: false, durationHours: nil)
    }
}

enum DashboardState {
    case loading
    case ready
    case error(String, retry: () async -> Void)
}

struct RunningSchedule {
    let name: String
    let zone: String
    let remainingSeconds: Int
    
    var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct UpcomingSchedule {
    let name: String
    let eta: Date
    
    var formattedETA: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: eta)
    }
}
