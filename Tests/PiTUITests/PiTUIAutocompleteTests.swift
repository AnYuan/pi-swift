import XCTest
import Foundation
@testable import PiTUI

final class PiTUIAutocompleteTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testForceExtractsRootSlashFromTrailingSpace() {
        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let result = provider.getForceFileSuggestions(lines: ["hey /"], cursorLine: 0, cursorCol: 5)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.prefix, "/")
    }

    func testForceDoesNotTriggerForSlashCommandAtLineStart() {
        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let result = provider.getForceFileSuggestions(lines: ["/model"], cursorLine: 0, cursorCol: 6)

        XCTAssertNil(result)
    }

    func testQuotesPathsWithSpacesForDirectCompletion() throws {
        try createDir("my folder")
        try createFile("my folder/test.txt")

        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let result = provider.getForceFileSuggestions(lines: ["my"], cursorLine: 0, cursorCol: 2)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.items.map(\.value).contains("\"my folder/\"") == true)
    }

    func testContinuesCompletionInsideQuotedPath() throws {
        try createDir("my folder")
        try createFile("my folder/test.txt")
        try createFile("my folder/other.txt")

        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let line = "\"my folder/\""
        let result = provider.getForceFileSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count - 1)

        XCTAssertNotNil(result)
        let values = result?.items.map(\.value) ?? []
        XCTAssertTrue(values.contains("\"my folder/test.txt\""))
        XCTAssertTrue(values.contains("\"my folder/other.txt\""))
    }

    func testAppliesQuotedCompletionWithoutDuplicatingClosingQuote() throws {
        try createDir("my folder")
        try createFile("my folder/test.txt")

        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let line = "\"my folder/te\""
        let cursorCol = line.count - 1
        let suggestions = provider.getForceFileSuggestions(lines: [line], cursorLine: 0, cursorCol: cursorCol)
        let item = suggestions?.items.first(where: { $0.value == "\"my folder/test.txt\"" })

        XCTAssertNotNil(item)
        let applied = provider.applyCompletion(
            lines: [line],
            cursorLine: 0,
            cursorCol: cursorCol,
            item: item!,
            prefix: suggestions!.prefix
        )
        XCTAssertEqual(applied.lines[0], "\"my folder/test.txt\"")
    }

    func testAtPathSuggestionsAddTrailingSpaceForFilesWhenApplied() throws {
        try createDir("src")
        try createFile("src/index.ts")

        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let suggestions = provider.getForceFileSuggestions(lines: ["@src/in"], cursorLine: 0, cursorCol: 7)
        let item = suggestions?.items.first(where: { $0.value == "@src/index.ts" })

        XCTAssertNotNil(item)
        let applied = provider.applyCompletion(
            lines: ["@src/in"],
            cursorLine: 0,
            cursorCol: 7,
            item: item!,
            prefix: suggestions!.prefix
        )
        XCTAssertEqual(applied.lines[0], "@src/index.ts ")
    }

    func testAtPathDirectoryCompletionKeepsCursorInsideClosingQuoteForContinuation() throws {
        try createDir("my folder")

        let provider = PiTUICombinedAutocompleteProvider(basePath: tempDir.path)
        let suggestions = provider.getForceFileSuggestions(lines: ["@my"], cursorLine: 0, cursorCol: 3)
        let item = suggestions?.items.first(where: { $0.value == "@\"my folder/\"" })

        XCTAssertNotNil(item)
        let applied = provider.applyCompletion(
            lines: ["@my"],
            cursorLine: 0,
            cursorCol: 3,
            item: item!,
            prefix: suggestions!.prefix
        )

        XCTAssertEqual(applied.lines[0], "@\"my folder/\"")
        XCTAssertEqual(applied.cursorCol, item!.value.count - 1)
    }

    private func createDir(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(relativePath, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func createFile(_ relativePath: String, contents: String = "x") throws {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try XCTUnwrap(contents.data(using: .utf8))
        try data.write(to: url)
    }
}
