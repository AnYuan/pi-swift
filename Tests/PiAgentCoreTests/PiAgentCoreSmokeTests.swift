import XCTest
@testable import PiAgentCore

final class PiAgentCoreSmokeTests: XCTestCase {
    func testDependenciesWireToAiAndCoreTypes() {
        XCTAssertEqual(PiAgentCoreModule.dependencies, ["PiCoreTypes", "PiAI"])
    }
}
