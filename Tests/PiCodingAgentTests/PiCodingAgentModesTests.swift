import XCTest
import Foundation
import PiAI
@testable import PiCodingAgent

final class PiCodingAgentModesTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testPrintModeBuildsDeterministicOutput() {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let output = runner.runPrint(.init(prompt: "hello", pipedInput: "stdin text"))

        XCTAssertTrue(output.contains("mode: print"))
        XCTAssertTrue(output.contains("prompt: hello"))
        XCTAssertTrue(output.contains("pipedInput: stdin text"))
    }

    func testJSONModeEmitsStructuredEvents() throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let output = runner.runJSON(.init(prompt: "hello", pipedInput: nil))

        let lines = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)

        let first = try parseObject(lines[0])
        XCTAssertEqual(first["type"] as? String, "mode.start")
        XCTAssertEqual(first["mode"] as? String, "json")

        let second = try parseObject(lines[1])
        XCTAssertEqual(second["type"] as? String, "input")
        XCTAssertEqual(second["prompt"] as? String, "hello")

        let third = try parseObject(lines[2])
        XCTAssertEqual(third["type"] as? String, "result")
        XCTAssertEqual(third["status"] as? String, "ok")
    }

    func testRPCPingReturnsOKResult() async throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try await runner.handleRPC(#"{"id":"1","method":"ping"}"#)
        let object = try parseObject(response)

        XCTAssertEqual(object["id"] as? String, "1")
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["version"] as? String, "pi-swift test")
    }

    func testRPCRunPrintDelegatesToPrintMode() async throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try await runner.handleRPC(#"{"id":"2","method":"run.print","params":{"prompt":"ship it"}} "#)
        let object = try parseObject(response)

        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let output = try XCTUnwrap(result["output"] as? String)
        XCTAssertTrue(output.contains("mode: print"))
        XCTAssertTrue(output.contains("prompt: ship it"))
    }

    func testRPCUnknownMethodReturnsErrorEnvelope() async throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try await runner.handleRPC(#"{"id":"3","method":"missing.method"}"#)
        let object = try parseObject(response)

        XCTAssertEqual(object["id"] as? String, "3")
        let error = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "method_not_found")
        XCTAssertTrue((error["message"] as? String)?.contains("missing.method") == true)
    }

    func testSDKFacadeExposesPrintAndJSONModes() {
        let sdk = PiCodingAgentSDK(runner: .init(version: "pi-swift test"))
        let print = sdk.runPrint(prompt: "hi")
        let json = sdk.runJSON(prompt: "hi")

        XCTAssertTrue(print.contains("mode: print"))
        XCTAssertTrue(json.contains("\"type\":\"mode.start\""))
    }

    func testRPCToolsListReturnsToolDefinitions() async throws {
        let registry = PiCodingAgentToolRegistry(tools: [
            PiFileReadTool(baseDirectory: tempDir.path),
            PiFileWriteTool(baseDirectory: tempDir.path)
        ])
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", toolRegistry: registry)
        let response = try await runner.handleRPC(#"{"id":"4","method":"tools.list"}"#)
        let object = try parseObject(response)

        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }.sorted()
        XCTAssertEqual(names, ["read", "write"])
    }

    func testRPCToolsExecuteRunsToolAndReturnsStructuredResult() async throws {
        let registry = PiCodingAgentToolRegistry(tools: [
            PiFileWriteTool(baseDirectory: tempDir.path)
        ])
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", toolRegistry: registry)
        let response = try await runner.handleRPC(#"{"id":"5","method":"tools.execute","params":{"id":"tc1","name":"write","arguments":{"path":"out.txt","content":"hello"}}}"#)
        let object = try parseObject(response)
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let text = try XCTUnwrap(result["text"] as? String)
        XCTAssertTrue(text.contains("Wrote"))
        XCTAssertEqual(try String(contentsOf: tempDir.appendingPathComponent("out.txt"), encoding: .utf8), "hello")
    }

    func testSDKFacadeCanListAndExecuteTools() async throws {
        let registry = PiCodingAgentToolRegistry(tools: [PiFileWriteTool(baseDirectory: tempDir.path)])
        let sdk = PiCodingAgentSDK(runner: .init(version: "pi-swift test", toolRegistry: registry))

        let tools = sdk.listTools()
        XCTAssertEqual(tools.map(\.name), ["write"])

        let result = try await sdk.executeTool(.init(
            id: "1",
            name: "write",
            arguments: .object(["path": .string("sdk.txt"), "content": .string("abc")])
        ))
        XCTAssertTrue((extractText(result) ?? "").contains("Wrote"))
    }

    func testRPCRunLocalUsesOpenAICompatibleRuntimeAndReturnsAssistantOutput() async throws {
        let transport = PiCodingAgentRecordingOpenAICompatibleTransport(responses: [
            makeOpenAICompatibleChatCompletionResponse(content: "local response")
        ])
        let runtime = PiCodingAgentOpenAICompatibleRuntime(
            provider: .init(transport: transport),
            timestamp: { 1_710_000_111 }
        )
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", localRuntime: runtime)
        let request = #"""
        {
          "id": "local-1",
          "method": "run.local",
          "params": {
            "prompt": "hello local",
            "baseURL": "http://127.0.0.1:1234",
            "model": "mlx-community/Qwen3.5-35B-A3B-bf16",
            "apiKey": "sk-local"
          }
        }
        """#

        let response = try await runner.handleRPC(request)
        let object = try parseObject(response)
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(result["output"] as? String, "local response")
        XCTAssertEqual(result["provider"] as? String, "openai-compatible")
        XCTAssertEqual(result["model"] as? String, "mlx-community/Qwen3.5-35B-A3B-bf16")

        let capturedRequest = await transport.lastRequest()
        XCTAssertEqual(capturedRequest?.url.absoluteString, "http://127.0.0.1:1234/v1/chat/completions")
        XCTAssertEqual(capturedRequest?.headers["Authorization"], "Bearer sk-local")
        let bodyData = try XCTUnwrap(capturedRequest?.body)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "mlx-community/Qwen3.5-35B-A3B-bf16")
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "hello local")
    }

    private func parseObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func extractText(_ result: PiCodingAgentToolResult) -> String? {
        guard result.content.count == 1 else { return nil }
        guard case .text(let content) = result.content[0] else { return nil }
        return content.text
    }
}
