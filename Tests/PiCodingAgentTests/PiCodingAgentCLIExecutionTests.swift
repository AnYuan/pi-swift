import XCTest
@testable import PiCodingAgent

final class PiCodingAgentCLIExecutionTests: XCTestCase {
    func testExecutePrintModeReturnsRenderedPrintOutput() {
        let result = PiCodingAgentCLIExecutor.execute(
            argv: ["--print", "ship"],
            env: .init(),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startPrint(prompt: "ship", pipedInput: nil))
        XCTAssertTrue(result.stdout.contains("mode: print"))
        XCTAssertTrue(result.stdout.contains("prompt: ship"))
    }

    func testExecuteJSONModeReturnsStructuredJSONOutput() {
        let result = PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "json", "hello"],
            env: .init(),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startJSON(prompt: "hello", pipedInput: nil))
        XCTAssertTrue(result.stdout.contains("\"type\":\"mode.start\""))
        XCTAssertTrue(result.stdout.contains("\"mode\":\"json\""))
    }

    func testExecuteRPCModeHandlesSingleRequestFromPipedStdin() {
        let result = PiCodingAgentCLIExecutor.execute(
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

    func testExecuteRPCModeReturnsProtocolErrorForInvalidJSONRequest() {
        let result = PiCodingAgentCLIExecutor.execute(
            argv: ["--mode", "rpc"],
            env: .init(stdinIsTTY: false, pipedStdin: "{ invalid"),
            modeRunner: .init(version: "pi-swift test")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startRPC)
        XCTAssertTrue(result.stdout.contains("\"error\""))
        XCTAssertTrue(result.stdout.contains("invalid_request"))
    }
}
