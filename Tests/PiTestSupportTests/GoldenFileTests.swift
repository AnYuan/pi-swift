import Foundation
import XCTest
@testable import PiTestSupport

final class GoldenFileTests: XCTestCase {
    func testReturnsMatchedForExistingGolden() throws {
        let loader = try FixtureLoader(callerFilePath: #filePath)

        let result = try GoldenFile.verifyText(
            "hello-golden\n",
            fixturePath: "goldens/example.txt",
            loader: loader,
            updateMode: .never
        )

        XCTAssertEqual(result, .matched)
    }

    func testThrowsMismatchWithDiffWhenGoldenDiffers() throws {
        let loader = try FixtureLoader(callerFilePath: #filePath)

        do {
            _ = try GoldenFile.verifyText(
                "hello-swift\n",
                fixturePath: "goldens/example.txt",
                loader: loader,
                updateMode: .never
            )
            XCTFail("Expected mismatch error")
        } catch let error as PiTestSupportError {
            switch error {
            case .goldenMismatch(let fixturePath, let diff):
                XCTAssertTrue(fixturePath.hasSuffix("Tests/Fixtures/goldens/example.txt"))
                XCTAssertTrue(diff.contains("-1| hello-golden"))
                XCTAssertTrue(diff.contains("+1| hello-swift"))
            default:
                XCTFail("Unexpected PiTestSupportError: \(error)")
            }
        }
    }

    func testCreatesAndUpdatesGoldenWhenUpdateModeAlways() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let loader = FixtureLoader(fixturesRootURL: tempRoot)

        let created = try GoldenFile.verifyText(
            "v1\n",
            fixturePath: "goldens/generated.txt",
            loader: loader,
            updateMode: .always
        )
        XCTAssertEqual(created, .created)
        XCTAssertEqual(try loader.loadText("goldens/generated.txt"), "v1\n")

        let updated = try GoldenFile.verifyText(
            "v2\n",
            fixturePath: "goldens/generated.txt",
            loader: loader,
            updateMode: .always
        )
        XCTAssertEqual(updated, .updated)
        XCTAssertEqual(try loader.loadText("goldens/generated.txt"), "v2\n")
    }
}

