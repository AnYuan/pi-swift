import XCTest
@testable import PiWebUIBridge

final class PiWebUIBridgeSmokeTests: XCTestCase {
    func testDependencyGraphMatchesPlan() {
        XCTAssertEqual(PiWebUIBridgeModule.dependencies, ["PiCoreTypes", "PiAI", "PiAgentCore"])
    }
}
