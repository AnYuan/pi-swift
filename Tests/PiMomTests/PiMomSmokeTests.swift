import XCTest
@testable import PiMom

final class PiMomSmokeTests: XCTestCase {
    func testDependencyGraphIncludesCodingAgent() {
        XCTAssertTrue(PiMomModule.dependencies.contains("PiCodingAgent"))
    }
}
