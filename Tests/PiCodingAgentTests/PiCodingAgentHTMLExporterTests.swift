import XCTest
import Foundation
import PiAI
import PiAgentCore
@testable import PiCodingAgent

final class PiCodingAgentHTMLExporterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-coding-agent-html-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testRenderSessionHTMLIncludesEscapedMessagesAndImages() throws {
        let session = makeSessionRecord(messages: [
            .user(.init(content: .parts([
                .text(.init(text: "hello <world>")),
                .image(.init(data: "Zm9v", mimeType: "image/png")),
            ]), timestamp: 1)),
            .assistant(.init(
                content: [
                    .thinking(.init(thinking: "reasoning")),
                    .text(.init(text: "done & shipped")),
                ],
                api: "responses",
                provider: "openai",
                model: "gpt-5",
                usage: .zero,
                stopReason: .stop,
                timestamp: 2
            )),
            .toolResult(.init(
                toolCallId: "call-1",
                toolName: "read",
                content: [.text(.init(text: "line1\nline2"))],
                details: .object(["path": .string("a.txt")]),
                isError: false,
                timestamp: 3
            ))
        ])

        let html = PiCodingAgentHTMLExporter.render(session: session)

        XCTAssertTrue(html.contains("<title>demo-session</title>"))
        XCTAssertTrue(html.contains("hello &lt;world&gt;"))
        XCTAssertTrue(html.contains("done &amp; shipped"))
        XCTAssertTrue(html.contains("toolResult"))
        XCTAssertTrue(html.contains("tool: read"))
        XCTAssertTrue(html.contains("data:image/png;base64,Zm9v"))
        XCTAssertTrue(html.contains("&quot;path&quot; : &quot;a.txt&quot;") || html.contains("&quot;path&quot;: &quot;a.txt&quot;"))
    }

    func testExportSessionFileWritesHTMLAndReturnsOutputPath() throws {
        let session = makeSessionRecord(messages: [.user(.init(content: .text("hi"), timestamp: 1))])
        let sessionURL = tempDir.appendingPathComponent("session.json")
        try writeSession(session, to: sessionURL)

        let outputPath = try PiCodingAgentHTMLExporter.exportSessionFile(at: sessionURL.path)

        XCTAssertEqual(outputPath, tempDir.appendingPathComponent("session.html").path)
        let html = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(html.contains("demo-session"))
        XCTAssertTrue(html.contains(">hi<"))
    }

    func testExportSessionFileSupportsExplicitOutputPath() throws {
        let session = makeSessionRecord(messages: [.user(.init(content: .text("x"), timestamp: 1))])
        let sessionURL = tempDir.appendingPathComponent("s.json")
        let outputURL = tempDir.appendingPathComponent("custom/output.html")
        try writeSession(session, to: sessionURL)

        let path = try PiCodingAgentHTMLExporter.exportSessionFile(at: sessionURL.path, outputPath: outputURL.path)

        XCTAssertEqual(path, outputURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testExportSessionFileErrorsOnUnsupportedFileType() throws {
        let inputURL = tempDir.appendingPathComponent("session.jsonl")
        try "[]".write(to: inputURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PiCodingAgentHTMLExporter.exportSessionFile(at: inputURL.path)) { error in
            XCTAssertEqual(error as? PiCodingAgentHTMLExporterError, .unsupportedInputFormat(inputURL.path))
        }
    }

    private func makeSessionRecord(messages: [PiAgentMessage]) -> PiCodingAgentSessionRecord {
        .init(
            id: "demo-session",
            title: "Demo",
            createdAt: .init(timeIntervalSince1970: 0),
            updatedAt: .init(timeIntervalSince1970: 1),
            state: .init(
                systemPrompt: "You are helpful",
                model: .init(provider: "openai", id: "gpt-5"),
                thinkingLevel: .low,
                tools: [],
                messages: messages,
                isStreaming: false,
                streamMessage: nil,
                pendingToolCalls: [],
                error: nil
            )
        )
    }

    private func writeSession(_ session: PiCodingAgentSessionRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url)
    }
}
