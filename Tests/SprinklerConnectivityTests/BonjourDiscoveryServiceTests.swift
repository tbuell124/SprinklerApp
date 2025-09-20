#if canImport(XCTest)
import XCTest
#if canImport(Sprink_)
@testable import Sprink_
#else
@testable import SprinklerConnectivity
#endif

final class BonjourDiscoveryServiceTests: XCTestCase {
    func testBaseURLPrefersHost() {
        let device = DiscoveredDevice(id: "sprinkler.local:8000", name: "sprinkler", host: "sprinkler.local", ip: "192.168.1.10", port: 8000)
        XCTAssertEqual(device.baseURLString, "http://sprinkler.local:8000")
    }

    func testBaseURLFallsBackToIPv6() {
        let device = DiscoveredDevice(id: "[fd00::1]:8000", name: "sprinkler", host: nil, ip: "fd00::1", port: 8000)
        XCTAssertEqual(device.baseURLString, "http://[fd00::1]:8000")
    }

    func testBaseURLStripsTrailingDotFromHost() {
        let device = DiscoveredDevice(id: "sprinkler.local.:8000", name: "sprinkler", host: "sprinkler.local.", ip: nil, port: 8000)
        XCTAssertEqual(device.baseURLString, "http://sprinkler.local:8000")
    }
}
#endif
