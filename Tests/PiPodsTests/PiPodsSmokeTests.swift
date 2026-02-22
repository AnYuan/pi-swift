import XCTest
@testable import PiPods

final class PiPodsSmokeTests: XCTestCase {
    func testDependencyGraphMatchesPlan() {
        XCTAssertEqual(PiPodsModule.dependencies, ["PiCoreTypes", "PiAI", "PiAgentCore"])
    }
}
