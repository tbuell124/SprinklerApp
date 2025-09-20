import XCTest
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

    private func makeStore() -> SprinklerStore {
        let suiteName = "SprinklerStoreTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return SprinklerStore(userDefaults: userDefaults,
                              keychain: KeychainStub(),
                              client: APIClient())
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
