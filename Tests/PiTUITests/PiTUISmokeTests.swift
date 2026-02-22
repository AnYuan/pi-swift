import XCTest
@testable import PiTUI

final class PiTUISmokeTests: XCTestCase {
    func testModuleExposesCoreDependencyMarker() {
        XCTAssertEqual(PiTUIModule.moduleName, "PiTUI")
        XCTAssertEqual(PiTUIModule.dependencyMarker.value, "PiCoreTypes")
    }
}
