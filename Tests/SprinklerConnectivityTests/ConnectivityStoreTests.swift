#if canImport(XCTest)
import XCTest
#if canImport(Sprink_)
@testable import Sprink_
#else
@testable import SprinklerConnectivity
#endif

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

    @MainActor
    func testNormalizedBaseURLStripsTrailingDot() {
        let url = ConnectivityStore.normalizedBaseURL(from: "http://sprinkler.local.:8000")
        XCTAssertEqual(url?.absoluteString, "http://sprinkler.local:8000")
    }

    func testConcurrentCallsDoNotTriggerMultipleChecks() async {
        let suiteName = "sprinkler.connectivity.concurrent"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let checker = SlowHealthChecker(result: .connected)
        let store = await ConnectivityStore(checker: checker, defaults: defaults)

        async let first: Void = store.testConnection()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await store.testConnection()
        _ = await first

        let invocations = await checker.invocationCount()
        XCTAssertEqual(invocations, 1)
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

private actor SlowHealthChecker: ConnectivityChecking {
    private let result: ConnectivityState
    private var calls = 0

    init(result: ConnectivityState) {
        self.result = result
    }

    func check(baseURL: URL) async -> ConnectivityState {
        calls += 1
        try? await Task.sleep(nanoseconds: 100_000_000)
        return result
    }

    func invocationCount() -> Int { calls }
}
#endif
