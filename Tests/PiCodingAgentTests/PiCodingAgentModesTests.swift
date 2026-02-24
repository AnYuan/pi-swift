import XCTest
@testable import PiCodingAgent

final class PiCodingAgentModesTests: XCTestCase {
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

    private func parseObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
