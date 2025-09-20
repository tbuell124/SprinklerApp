import XCTest
@testable import Sprink

final class PinCatalogMergerTests: XCTestCase {
    func testMergePreservesRemotePinsAndOrder() {
        let current: [PinDTO] = [
            PinDTO(pin: 4, name: "Legacy", isActive: false, isEnabled: true)
        ]

        let remote: [PinDTO] = [
            PinDTO(pin: 12, name: "Front Yard", isActive: true, isEnabled: true),
            PinDTO(pin: 16, name: "Back Yard", isActive: false, isEnabled: true)
        ]

        let merged = PinCatalogMerger.merge(current: current, remote: remote)

        XCTAssertEqual(merged.map(\.pin), [12, 16])
        XCTAssertEqual(merged.map { $0.name }, ["Front Yard", "Back Yard"])
        XCTAssertEqual(merged.map { $0.isActive }, [true, false])
    }

    func testMergeFallsBackToExistingWhenRemoteMissing() {
        let current: [PinDTO] = [
            PinDTO(pin: 4, name: "Zone 1", isActive: false, isEnabled: true)
        ]

        let merged = PinCatalogMerger.merge(current: current, remote: nil)

        XCTAssertEqual(merged, current)
    }

    func testMergeUsesDefaultCatalogWhenNoStateAvailable() {
        let merged = PinCatalogMerger.merge(current: [], remote: nil)
        XCTAssertEqual(merged, PinDTO.makeDefaultSprinklerPins())
    }

    func testMergePreservesExistingMetadataWhenRemoteOmitsIt() {
        let current: [PinDTO] = [
            PinDTO(pin: 12, name: "Custom Name", isActive: true, isEnabled: false)
        ]

        let remote: [PinDTO] = [
            PinDTO(pin: 12, name: nil, isActive: nil, isEnabled: nil)
        ]

        let merged = PinCatalogMerger.merge(current: current, remote: remote)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.pin, 12)
        XCTAssertEqual(merged.first?.name, "Custom Name")
        XCTAssertEqual(merged.first?.isActive, true)
        XCTAssertEqual(merged.first?.isEnabled, false)
    }
}
