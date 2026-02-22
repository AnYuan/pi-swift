import XCTest
@testable import PiCoreTypes

final class PiCoreTypesSmokeTests: XCTestCase {
    func testMarkerRoundTrip() {
        let marker = PiCoreTypesModule.Marker(value: "core")
        XCTAssertEqual(marker, .init(value: "core"))
    }
}
