import XCTest
@testable import PiCodingAgent

final class PiCodingAgentSmokeTests: XCTestCase {
    func testBootMessageAndDependencyGraph() {
        XCTAssertEqual(PiCodingAgentModule.bootMessage(), "PiCodingAgent skeleton initialized")
        XCTAssertEqual(PiCodingAgentModule.dependencies, ["PiCoreTypes", "PiAI", "PiAgentCore", "PiTUI"])
    }
}
