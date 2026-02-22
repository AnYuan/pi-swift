import XCTest
@testable import PiAI

final class PiAISmokeTests: XCTestCase {
    func testModuleExposesDependencyMarker() {
        XCTAssertEqual(PiAIModule.moduleName, "PiAI")
        XCTAssertEqual(PiAIModule.dependencyMarker.value, "PiCoreTypes")
    }
}
