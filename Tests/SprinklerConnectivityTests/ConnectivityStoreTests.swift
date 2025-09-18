#if canImport(XCTest)
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

        let checker = MockHealthChecker(result: .connected)
        let store = await ConnectivityStore(checker: checker, defaults: defaults)

        await MainActor.run {
            store.baseURLString = "http://example.local:8080"
        }
        await store.testConnection()

        let savedValue = defaults.string(forKey: "sprinkler.baseURL")
        XCTAssertEqual(savedValue, "http://example.local:8080")
    }

    @MainActor
    func testNormalizedBaseURLAddsSchemeWhenMissing() {
        let url = ConnectivityStore.normalizedBaseURL(from: "sprinkler.local:1234")
        XCTAssertEqual(url?.absoluteString, "http://sprinkler.local:1234")
    }
}

private actor MockHealthChecker: ConnectivityChecking {
    let result: ConnectivityState

    init(result: ConnectivityState) {
        self.result = result
    }

    func check(baseURL: URL) async -> ConnectivityState {
        return result
    }
}
#endif
