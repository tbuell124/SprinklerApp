import XCTest
@testable import SprinklerConnectivity

final class BonjourDiscoveryServiceTests: XCTestCase {
    func testFilterMatchesSprinklerName() {
        XCTAssertTrue(BonjourDiscoveryService.isSprinklerService(name: "Sprinkler Controller", host: nil))
    }

    func testFilterMatchesSprinklerHost() {
        XCTAssertTrue(BonjourDiscoveryService.isSprinklerService(name: "Garden", host: "sprinkler.local"))
    }

    func testFilterRejectsNonSprinklerService() {
        XCTAssertFalse(BonjourDiscoveryService.isSprinklerService(name: "Garden", host: "controller.local"))
    }

    func testBaseURLPrefersHostName() {
        let device = DiscoveredDevice(
            id: "sprinkler.local:8000",
            name: "sprinkler",
            host: "sprinkler.local",
            ip: "192.168.1.10",
            port: 8000
        )
        XCTAssertEqual(device.baseURLString, "http://sprinkler.local:8000")
    }

    func testBaseURLFallsBackToIPAddress() {
        let device = DiscoveredDevice(
            id: "sprinkler:8000",
            name: "sprinkler",
            host: nil,
            ip: "192.168.1.20",
            port: 8000
        )
        XCTAssertEqual(device.baseURLString, "http://192.168.1.20:8000")
    }

    func testBaseURLWrapsIPv6AddressInBrackets() {
        let device = DiscoveredDevice(
            id: "sprinkler:8000",
            name: "sprinkler",
            host: nil,
            ip: "fe80::1",
            port: 8000
        )
        XCTAssertEqual(device.baseURLString, "http://[fe80::1]:8000")
    }
}
