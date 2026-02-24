import XCTest
import Foundation
@testable import PiCodingAgent

final class PiCodingAgentFileProcessorTests: XCTestCase {
    private static let tinyPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-coding-agent-file-processor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testProcessesTextFilesIntoWrappedText() throws {
        let textURL = tempDir.appendingPathComponent("prompt.md")
        try "# Hello\nworld".write(to: textURL, atomically: true, encoding: .utf8)

        let result = try PiCodingAgentFileProcessor.processFileArguments([textURL.path], currentDirectory: tempDir.path)

        XCTAssertEqual(result.images, [])
        XCTAssertEqual(result.text, """
        <file name="\(textURL.path)">
        # Hello
        world
        </file>
        
        """)
    }

    func testProcessesImageFilesIntoAttachmentsAndFileReferences() throws {
        let imageURL = tempDir.appendingPathComponent("tiny.png")
        try Data(base64Encoded: Self.tinyPNGBase64).unwrap().write(to: imageURL)

        let result = try PiCodingAgentFileProcessor.processFileArguments([imageURL.path], currentDirectory: tempDir.path)

        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].mimeType, "image/png")
        XCTAssertEqual(result.images[0].data, Self.tinyPNGBase64)
        XCTAssertEqual(result.text, "<file name=\"\(imageURL.path)\"></file>\n")
    }

    func testSkipsEmptyFiles() throws {
        let emptyURL = tempDir.appendingPathComponent("empty.txt")
        try Data().write(to: emptyURL)

        let result = try PiCodingAgentFileProcessor.processFileArguments([emptyURL.path], currentDirectory: tempDir.path)

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.images, [])
    }

    func testThrowsForMissingFileWithResolvedPath() {
        let missingPath = tempDir.appendingPathComponent("missing.txt").path

        XCTAssertThrowsError(try PiCodingAgentFileProcessor.processFileArguments([missingPath], currentDirectory: tempDir.path)) { error in
            XCTAssertEqual(error as? PiCodingAgentFileProcessorError, .fileNotFound(missingPath))
        }
    }

    func testThrowsForNonUTF8NonImageFile() throws {
        let binaryURL = tempDir.appendingPathComponent("blob.bin")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: binaryURL)

        XCTAssertThrowsError(try PiCodingAgentFileProcessor.processFileArguments([binaryURL.path], currentDirectory: tempDir.path)) { error in
            XCTAssertEqual(error as? PiCodingAgentFileProcessorError, .unsupportedTextEncoding(binaryURL.path))
        }
    }

    func testResolvesRelativeAndTildePaths() throws {
        let nested = tempDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let textURL = nested.appendingPathComponent("note.txt")
        try "abc".write(to: textURL, atomically: true, encoding: .utf8)

        let homeRelative = textURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let relativePath = "nested/note.txt"

        let result = try PiCodingAgentFileProcessor.processFileArguments([relativePath, homeRelative], currentDirectory: tempDir.path)
        XCTAssertTrue(result.text.contains("<file name=\"\(textURL.path)\">"))
        XCTAssertEqual(result.images, [])
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        guard let value = self else {
            XCTFail("Expected non-nil value", file: file, line: line)
            throw NSError(domain: "PiCodingAgentFileProcessorTests", code: 1)
        }
        return value
    }
}
