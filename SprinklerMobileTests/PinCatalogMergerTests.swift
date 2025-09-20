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

        XCTAssertEqual(merged.count, PinDTO.sprinklerSafeOutputPins.count)
        XCTAssertEqual(merged.prefix(2).map(\.pin), [12, 16])
        XCTAssertEqual(merged.prefix(2).map { $0.name }, ["Front Yard", "Back Yard"])
        XCTAssertEqual(merged.prefix(2).map { $0.isActive }, [true, false])

        let appended = merged.dropFirst(2)
        XCTAssertFalse(appended.contains { $0.isEnabled ?? true })
        let expectedRemainingPins = Set(PinDTO.sprinklerSafeOutputPins).subtracting([12, 16])
        XCTAssertEqual(Set(appended.map(\.pin)), expectedRemainingPins)
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
        XCTAssertEqual(merged.count, PinDTO.sprinklerSafeOutputPins.count)
        XCTAssertEqual(merged.first?.pin, 12)
        XCTAssertEqual(merged.first?.name, "Custom Name")
        XCTAssertEqual(merged.first?.isActive, true)
        XCTAssertEqual(merged.first?.isEnabled, false)

        let appended = merged.dropFirst()
        XCTAssertTrue(appended.allSatisfy { ($0.isEnabled ?? false) == false })
    }
}
