import Foundation
import XCTest
@testable import PiTestSupport

final class FixtureLoaderTests: XCTestCase {
    func testLoadsTextFixtureFromRepositoryConventions() throws {
        let loader = try FixtureLoader(callerFilePath: #filePath)

        let text = try loader.loadText("common/sample.txt")

        XCTAssertEqual(text, "sample-fixture\n")
    }

    func testWritesAndReadsFixtureTextInTemporaryDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let loader = FixtureLoader(fixturesRootURL: tempRoot)

        try loader.writeText("generated", to: "generated/output.txt")
        let roundTrip = try loader.loadText("generated/output.txt")

        XCTAssertEqual(roundTrip, "generated")
    }
}

