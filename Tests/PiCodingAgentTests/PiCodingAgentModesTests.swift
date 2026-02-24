import XCTest
import Foundation
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

    func testRPCPingReturnsOKResult() throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try runner.handleRPC(#"{"id":"1","method":"ping"}"#)
        let object = try parseObject(response)

        XCTAssertEqual(object["id"] as? String, "1")
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["version"] as? String, "pi-swift test")
    }

    func testRPCRunPrintDelegatesToPrintMode() throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try runner.handleRPC(#"{"id":"2","method":"run.print","params":{"prompt":"ship it"}} "#)
        let object = try parseObject(response)

        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let output = try XCTUnwrap(result["output"] as? String)
        XCTAssertTrue(output.contains("mode: print"))
        XCTAssertTrue(output.contains("prompt: ship it"))
    }

    func testRPCUnknownMethodReturnsErrorEnvelope() throws {
        let runner = PiCodingAgentModeRunner(version: "pi-swift test")
        let response = try runner.handleRPC(#"{"id":"3","method":"missing.method"}"#)
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

    func testRPCToolsListReturnsToolDefinitions() throws {
        let registry = PiCodingAgentToolRegistry(tools: [
            PiFileReadTool(baseDirectory: tempDir.path),
            PiFileWriteTool(baseDirectory: tempDir.path)
        ])
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", toolRegistry: registry)
        let response = try runner.handleRPC(#"{"id":"4","method":"tools.list"}"#)
        let object = try parseObject(response)

        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }.sorted()
        XCTAssertEqual(names, ["read", "write"])
    }

    func testRPCToolsExecuteRunsToolAndReturnsStructuredResult() throws {
        let registry = PiCodingAgentToolRegistry(tools: [
            PiFileWriteTool(baseDirectory: tempDir.path)
        ])
        let runner = PiCodingAgentModeRunner(version: "pi-swift test", toolRegistry: registry)
        let response = try runner.handleRPC(#"{"id":"5","method":"tools.execute","params":{"id":"tc1","name":"write","arguments":{"path":"out.txt","content":"hello"}}}"#)
        let object = try parseObject(response)
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        let text = try XCTUnwrap(result["text"] as? String)
        XCTAssertTrue(text.contains("Wrote"))
        XCTAssertEqual(try String(contentsOf: tempDir.appendingPathComponent("out.txt"), encoding: .utf8), "hello")
    }

    func testSDKFacadeCanListAndExecuteTools() throws {
        let registry = PiCodingAgentToolRegistry(tools: [PiFileWriteTool(baseDirectory: tempDir.path)])
        let sdk = PiCodingAgentSDK(runner: .init(version: "pi-swift test", toolRegistry: registry))

        let tools = sdk.listTools()
        XCTAssertEqual(tools.map(\.name), ["write"])

        let result = try sdk.executeTool(.init(
            id: "1",
            name: "write",
            arguments: .object(["path": .string("sdk.txt"), "content": .string("abc")])
        ))
        XCTAssertTrue((extractText(result) ?? "").contains("Wrote"))
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
