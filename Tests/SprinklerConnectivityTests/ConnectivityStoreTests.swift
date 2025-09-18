import XCTest
@testable import SprinklerConnectivity

final class ConnectivityStoreTests: XCTestCase {
    func testBaseURLPersistsToUserDefaults() async {
        let suiteName = "sprinkler.connectivity.tests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let healthChecker = MockHealthChecker(result: .connected)
        let store = await ConnectivityStore(userDefaults: defaults, healthChecker: healthChecker)

        await MainActor.run {
            store.baseURLString = "http://example.local:8080"
        }
        await store.testConnection()

        let savedValue = defaults.string(forKey: "sprinkler.baseURL")
        XCTAssertEqual(savedValue, "http://example.local:8080")
    }
}

private actor MockHealthChecker: HealthChecking {
    let result: ConnectivityState

    init(result: ConnectivityState) {
        self.result = result
    }

    func check(baseURL: URL) async -> ConnectivityState {
        return result
    }
}
