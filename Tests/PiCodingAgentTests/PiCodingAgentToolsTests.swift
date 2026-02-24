import XCTest
import Foundation
import PiCoreTypes
@testable import PiCodingAgent

final class PiCodingAgentToolsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testRegistryListsDefinitionsAndDispatchesReadTool() throws {
        let fileURL = tempDir.appendingPathComponent("notes.txt")
        try "line1\nline2\nline3".write(to: fileURL, atomically: true, encoding: .utf8)

        let registry = PiCodingAgentToolRegistry(tools: [PiFileReadTool(baseDirectory: tempDir.path)])
        XCTAssertEqual(registry.listDefinitions().map(\.name), ["read"])

        let result = try registry.execute(.init(
            id: "1",
            name: "read",
            arguments: .object(["path": .string("notes.txt")])
        ))
        XCTAssertEqual(result.content, [.text(.init(text: "line1\nline2\nline3"))])
    }

    func testReadToolSupportsOffsetAndLimitWithTruncationDetails() throws {
        try "a\nb\nc\nd".write(to: tempDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let tool = PiFileReadTool(baseDirectory: tempDir.path)

        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("f.txt"),
                "offset": .number(1),
                "limit": .number(2),
            ])
        )

        let text = try XCTUnwrap(extractText(result))
        XCTAssertTrue(text.contains("b\nc"))
        XCTAssertTrue(text.contains("truncated"))
        if case .object(let details)? = result.details,
           case .object(let truncation)? = details["truncation"] {
            XCTAssertEqual(truncation["offset"], .number(1))
            XCTAssertEqual(truncation["limit"], .number(2))
        } else {
            XCTFail("Expected truncation details")
        }
    }

    func testReadToolErrorsWhenOffsetBeyondEOF() throws {
        try "x".write(to: tempDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let tool = PiFileReadTool(baseDirectory: tempDir.path)

        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("f.txt"),
                "offset": .number(5)
            ])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("offset 5 is beyond end of file"))
        }
    }

    func testWriteToolCreatesParentDirectoriesAndWritesFile() throws {
        let tool = PiFileWriteTool(baseDirectory: tempDir.path)
        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("nested/dir/out.txt"),
                "content": .string("hello")
            ])
        )

        let written = try String(contentsOf: tempDir.appendingPathComponent("nested/dir/out.txt"), encoding: .utf8)
        XCTAssertEqual(written, "hello")
        XCTAssertEqual(extractText(result), "Wrote 5 bytes to nested/dir/out.txt")
    }

    func testRegistryErrorsForUnknownTool() {
        let registry = PiCodingAgentToolRegistry()
        XCTAssertThrowsError(try registry.execute(.init(id: "1", name: "missing", arguments: .object([:])))) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .unknownTool("missing"))
        }
    }

    func testBashToolRunsCommandAndReturnsOutput() throws {
        let tool = PiBashTool(configuration: .init(workingDirectory: tempDir.path, shellPath: "/bin/zsh"))
        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object(["command": .string("printf 'hello'")])
        )
        XCTAssertEqual(extractText(result), "hello")
        if case .object(let details)? = result.details {
            XCTAssertEqual(details["exitCode"], .number(0))
        } else {
            XCTFail("Missing bash details")
        }
    }

    func testBashToolCommandPrefixIsPrepended() throws {
        let tool = PiBashTool(configuration: .init(
            workingDirectory: tempDir.path,
            shellPath: "/bin/zsh",
            commandPrefix: "export FOO=bar"
        ))
        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object(["command": .string("printf \"$FOO\"")])
        )
        XCTAssertEqual(extractText(result), "bar")
    }

    func testBashToolErrorsOnNonZeroExit() {
        let tool = PiBashTool(configuration: .init(workingDirectory: tempDir.path, shellPath: "/bin/zsh"))
        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object(["command": .string("printf err && exit 7")])
        )) { error in
            let message = (error as? PiCodingAgentToolError)?.description ?? ""
            XCTAssertTrue(message.contains("exit code 7"))
        }
    }

    func testBashToolErrorsOnTimeout() {
        let tool = PiBashTool(configuration: .init(workingDirectory: tempDir.path, shellPath: "/bin/zsh"))
        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "command": .string("sleep 2"),
                "timeout": .number(0.2)
            ])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("Command timed out after 0s"))
        }
    }

    func testBashToolErrorsWhenWorkingDirectoryMissing() {
        let missing = tempDir.appendingPathComponent("missing").path
        let tool = PiBashTool(configuration: .init(workingDirectory: missing, shellPath: "/bin/zsh"))
        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object(["command": .string("pwd")])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("Working directory not found: \(missing)"))
        }
    }

    func testBashToolErrorsWhenShellInvalid() {
        let tool = PiBashTool(configuration: .init(workingDirectory: tempDir.path, shellPath: "/path/does/not/exist"))
        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object(["command": .string("pwd")])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("Failed to spawn shell: /path/does/not/exist"))
        }
    }

    func testEditToolReplacesUniqueMatchAndReturnsDiffDetails() throws {
        let url = tempDir.appendingPathComponent("edit.txt")
        try "hello\nworld\n".write(to: url, atomically: true, encoding: .utf8)
        let tool = PiFileEditTool(baseDirectory: tempDir.path)

        let result = try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("edit.txt"),
                "oldText": .string("world"),
                "newText": .string("swift")
            ])
        )

        let updated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(updated, "hello\nswift\n")
        XCTAssertEqual(extractText(result), "Edited edit.txt")
        if case .object(let details)? = result.details {
            XCTAssertEqual(details["replacements"], .number(1))
            if case .string(let diff)? = details["diff"] {
                XCTAssertTrue(diff.contains("- world"))
                XCTAssertTrue(diff.contains("+ swift"))
            } else {
                XCTFail("Missing diff")
            }
        } else {
            XCTFail("Missing details")
        }
    }

    func testEditToolErrorsWhenOldTextMissing() throws {
        try "abc".write(to: tempDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let tool = PiFileEditTool(baseDirectory: tempDir.path)

        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("f.txt"),
                "oldText": .string("zzz"),
                "newText": .string("x"),
            ])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("oldText not found in f.txt"))
        }
    }

    func testEditToolErrorsWhenOldTextMatchesMultipleLocations() throws {
        try "x x x".write(to: tempDir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let tool = PiFileEditTool(baseDirectory: tempDir.path)

        XCTAssertThrowsError(try tool.execute(
            toolCallID: "1",
            arguments: .object([
                "path": .string("f.txt"),
                "oldText": .string("x"),
                "newText": .string("y"),
            ])
        )) { error in
            XCTAssertEqual(error as? PiCodingAgentToolError, .io("oldText matched multiple locations in f.txt"))
        }
    }

    private func extractText(_ result: PiCodingAgentToolResult) -> String? {
        guard result.content.count == 1 else { return nil }
        guard case .text(let content) = result.content[0] else { return nil }
        return content.text
    }
}
