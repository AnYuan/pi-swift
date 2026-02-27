import XCTest
import Foundation
import PiAI
import PiAgentCore
@testable import PiCodingAgent

final class PiCodingAgentCLIExecutionTests: XCTestCase {
    func testExecutePrintModeReturnsRenderedPrintOutput() async {
        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--print", "ship"],
            env: .init(),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startPrint(prompt: "ship", pipedInput: nil))
        XCTAssertTrue(result.stdout.contains("mode: print"))
        XCTAssertTrue(result.stdout.contains("prompt: ship"))
    }

    func testExecuteJSONModeReturnsStructuredJSONOutput() async {
        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "json", "hello"],
            env: .init(),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startJSON(prompt: "hello", pipedInput: nil))
        XCTAssertTrue(result.stdout.contains("\"type\":\"mode.start\""))
        XCTAssertTrue(result.stdout.contains("\"mode\":\"json\""))
    }

    func testExecuteRPCModeHandlesSingleRequestFromPipedStdin() async {
        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "rpc"],
            env: .init(stdinIsTTY: false, pipedStdin: #"{"id":"1","method":"ping"}"#),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startRPC)
        XCTAssertTrue(result.stdout.contains("\"id\":\"1\""))
        XCTAssertTrue(result.stdout.contains("\"result\""))
        XCTAssertTrue(result.stdout.contains("\"version\":\"pi-swift test\""))
    }

    func testExecuteRPCModeReturnsProtocolErrorForInvalidJSONRequest() async {
        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "rpc"],
            env: .init(stdinIsTTY: false, pipedStdin: "{ invalid"),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startRPC)
        XCTAssertTrue(result.stdout.contains("\"error\""))
        XCTAssertTrue(result.stdout.contains("invalid_request"))
    }

    func testExecuteRPCModeRunLocalBridgesOpenAICompatibleAdapter() async throws {
        let transport = PiCodingAgentRecordingOpenAICompatibleTransport(responses: [
            makeOpenAICompatibleChatCompletionResponse(content: "smoke ok")
        ])
        let runtime = PiCodingAgentOpenAICompatibleRuntime(
            provider: .init(transport: transport),
            timestamp: { 1_710_001_234 }
        )
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", localRuntime: runtime)
        let rpcRequest = #"""
        {
          "id": "smoke-1",
          "method": "run.local",
          "params": {
            "prompt": "smoke prompt",
            "baseURL": "http://127.0.0.1:1234",
            "model": "mlx-community/Qwen3.5-35B-A3B-bf16"
          }
        }
        """#

        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "rpc"],
            env: .init(stdinIsTTY: false, pipedStdin: rpcRequest),
            modeRunner: runner
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startRPC)
        XCTAssertTrue(result.stdout.contains("\"id\":\"smoke-1\""))
        XCTAssertTrue(result.stdout.contains("\"output\":\"smoke ok\""))

        let request = await transport.lastRequest()
        XCTAssertEqual(request?.url.absoluteString, "http://127.0.0.1:1234/v1/chat/completions")
    }

    func testExecuteExportModeWritesHTMLAndPrintsOutputPath() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionURL = tempDir.appendingPathComponent("session.json")
        let outputURL = tempDir.appendingPathComponent("session-export.html")
        try writeSessionFixture(to: sessionURL)

        let result = await PiCodingAgentCLIExecutor.execute(
            argv: ["--export", sessionURL.path, outputURL.path],
            env: .init(),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .exportHTML(inputPath: sessionURL.path, outputPath: outputURL.path))
        XCTAssertTrue(result.stdout.contains(outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }
}

private func writeSessionFixture(to url: URL) throws {
    let state = PiAgentState.empty(model: .init(provider: "openai", id: "gpt-5"), systemPrompt: "demo")
    let record = PiCodingAgentSessionRecord(
        id: "cli-export",
        title: "CLI Export",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 1),
        state: .init(
            systemPrompt: state.systemPrompt,
            model: state.model,
            thinkingLevel: state.thinkingLevel,
            tools: [],
            messages: [.user(.init(content: .text("hello"), timestamp: 1))],
            isStreaming: false,
            streamMessage: nil,
            pendingToolCalls: [],
            error: nil
        )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    try data.write(to: url)
}
