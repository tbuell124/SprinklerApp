import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import Sprink

@MainActor
final class SprinklerStoreTests: XCTestCase {
    func testScheduleRunTimeAcrossMidnight() {
        let store = makeStore()
        let pins = [
            PinDTO(pin: 4, name: "Front Lawn", isActive: nil, isEnabled: true),
            PinDTO(pin: 5, name: "Back Lawn", isActive: nil, isEnabled: true)
        ]
        let scheduleDTO = ScheduleDTO(
            id: "sequence-midnight",
            name: "Overnight Soak",
            runTimeMinutes: nil,
            startTime: "23:30",
            days: ["Mon"],
            isEnabled: true,
            sequence: [
                ScheduleSequenceItemDTO(pin: 4, durationMinutes: 45),
                ScheduleSequenceItemDTO(pin: 5, durationMinutes: 90)
            ]
        )

        let schedule = Schedule(dto: scheduleDTO, defaultPins: pins)
        store.configureForTesting(pins: pins, schedules: [schedule])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2024, month: 5, day: 6, hour: 22))!

        let runs = store.scheduleOccurrences(relativeTo: reference, calendar: calendar)
        guard let run = runs.first(where: { $0.schedule.id == schedule.id }) else {
            return XCTFail("Expected schedule run to be generated")
        }

        let expectedEnd = calendar.date(from: DateComponents(year: 2024, month: 5, day: 7, hour: 1, minute: 45))!
        XCTAssertEqual(run.startDate, calendar.date(from: DateComponents(year: 2024, month: 5, day: 6, hour: 23, minute: 30)))
        XCTAssertEqual(run.endDate, expectedEnd)
    }

    func testRunTimeUsesDirectDuration() {
        let store = makeStore()
        let pins = [
            PinDTO(pin: 4, name: "Front Lawn", isActive: nil, isEnabled: true),
            PinDTO(pin: 5, name: "Back Lawn", isActive: nil, isEnabled: true),
            PinDTO(pin: 6, name: "Side Yard", isActive: nil, isEnabled: false)
        ]
        let legacyDTO = ScheduleDTO(
            id: "legacy",
            name: "Legacy",
            runTimeMinutes: 15,
            startTime: "06:00",
            days: ["Tue"],
            isEnabled: true,
            sequence: nil
        )

        let legacySchedule = Schedule(dto: legacyDTO, defaultPins: pins)
        store.configureForTesting(pins: pins, schedules: [legacySchedule])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2024, month: 5, day: 7, hour: 5))!

        let runs = store.scheduleOccurrences(relativeTo: reference, calendar: calendar)
        guard let run = runs.first(where: { $0.schedule.id == legacySchedule.id }) else {
            return XCTFail("Expected legacy schedule run to be generated")
        }

        let expectedEnd = calendar.date(from: DateComponents(year: 2024, month: 5, day: 7, hour: 6, minute: 15))!
        XCTAssertEqual(run.startDate, calendar.date(from: DateComponents(year: 2024, month: 5, day: 7, hour: 6, minute: 0)))
        XCTAssertEqual(run.endDate, expectedEnd)
    }

    func testCreatingSchedulePersistsAcrossStoreInstances() async {
        let environment = try? TemporaryHomeEnvironment()
        XCTAssertNotNil(environment, "Failed to create temporary home directory")
        guard let environment else { return }
        defer { environment.restore() }

        let suiteName = "SprinklerStoreTests-Create"
        let store = makeStore(suiteName: suiteName, clearSuite: true)

        var draft = ScheduleDraft(pins: store.pins)
        draft.name = "Morning Water"
        draft.runTimeMinutes = 18
        draft.startTime = "06:15"
        draft.days = ["Mon", "Wed"]
        store.upsertSchedule(draft)

        XCTAssertEqual(store.schedules.count, 1)

        await waitForPersistence()

        let reloadedStore = makeStore(suiteName: suiteName, clearSuite: false)
        XCTAssertEqual(reloadedStore.schedules.count, 1)
        guard let persisted = reloadedStore.schedules.first else {
            return XCTFail("Expected schedule to persist across instances")
        }
        XCTAssertEqual(persisted.name, "Morning Water")
        XCTAssertEqual(persisted.runTimeMinutes, 18)

        cleanupUserDefaults(suiteName: suiteName)
    }

    func testEditingScheduleUpdatesPersistedState() async {
        let environment = try? TemporaryHomeEnvironment()
        XCTAssertNotNil(environment, "Failed to create temporary home directory")
        guard let environment else { return }
        defer { environment.restore() }

        let suiteName = "SprinklerStoreTests-Edit"
        let store = makeStore(suiteName: suiteName, clearSuite: true)

        var draft = ScheduleDraft(pins: store.pins)
        draft.name = "Evening Soak"
        draft.runTimeMinutes = 20
        draft.startTime = "19:30"
        draft.days = ["Tue"]
        store.upsertSchedule(draft)

        await waitForPersistence()

        guard let initial = store.schedules.first else {
            return XCTFail("Expected schedule to exist after creation")
        }

        var editedDraft = ScheduleDraft(schedule: initial, pins: store.pins)
        editedDraft.runTimeMinutes = 35
        editedDraft.days = ["Tue", "Thu"]
        store.upsertSchedule(editedDraft)

        await waitForPersistence()

        let reloadedStore = makeStore(suiteName: suiteName, clearSuite: false)
        guard let persisted = reloadedStore.schedules.first else {
            return XCTFail("Expected edited schedule to persist")
        }
        XCTAssertEqual(persisted.runTimeMinutes, 35)
        XCTAssertEqual(persisted.days, ["Tue", "Thu"])

        cleanupUserDefaults(suiteName: suiteName)
    }

    func testDeletingScheduleRemovesPersistedState() async {
        let environment = try? TemporaryHomeEnvironment()
        XCTAssertNotNil(environment, "Failed to create temporary home directory")
        guard let environment else { return }
        defer { environment.restore() }

        let suiteName = "SprinklerStoreTests-Delete"
        let store = makeStore(suiteName: suiteName, clearSuite: true)

        var draft = ScheduleDraft(pins: store.pins)
        draft.name = "Weekend Water"
        draft.runTimeMinutes = 25
        draft.startTime = "08:00"
        draft.days = ["Sat"]
        store.upsertSchedule(draft)

        await waitForPersistence()

        guard let created = store.schedules.first else {
            return XCTFail("Expected schedule to exist for deletion test")
        }

        store.deleteSchedule(created)
        XCTAssertTrue(store.schedules.isEmpty)

        await waitForPersistence()

        let reloadedStore = makeStore(suiteName: suiteName, clearSuite: false)
        XCTAssertTrue(reloadedStore.schedules.isEmpty)

        cleanupUserDefaults(suiteName: suiteName)
    }

    private func makeStore() -> SprinklerStore {
        return makeStore(suiteName: "SprinklerStoreTests-\(UUID().uuidString)", clearSuite: true)
    }

    private func makeStore(suiteName: String, clearSuite: Bool) -> SprinklerStore {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        if clearSuite {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return SprinklerStore(userDefaults: userDefaults,
                              keychain: KeychainStub(),
                              client: APIClient())
    }

    private func cleanupUserDefaults(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
    }

    private func waitForPersistence() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }
}

private final class KeychainStub: KeychainStoring {
    private var storage: [String: String] = [:]

    func string(forKey key: String) -> String? {
        storage[key]
    }

    func set(_ value: String, forKey key: String) throws {
        storage[key] = value
    }

    func deleteValue(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

private final class TemporaryHomeEnvironment {
    private let originalHome: String?
    private let originalXDGDataHome: String?
    private let temporaryURL: URL

    init(fileManager: FileManager = .default) throws {
        self.originalHome = ProcessInfo.processInfo.environment["HOME"]
        self.originalXDGDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        let base = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.temporaryURL = base
        setenv("HOME", base.path, 1)
        setenv("XDG_DATA_HOME", base.path, 1)
    }

    func restore(fileManager: FileManager = .default) {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        } else {
            unsetenv("HOME")
        }
        if let originalXDGDataHome {
            setenv("XDG_DATA_HOME", originalXDGDataHome, 1)
        } else {
            unsetenv("XDG_DATA_HOME")
        }
        try? fileManager.removeItem(at: temporaryURL)
    }
}
