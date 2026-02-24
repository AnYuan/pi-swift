import XCTest
@testable import PiCodingAgent

final class PiCodingAgentCLITests: XCTestCase {
    func testHelpFlagReturnsHelpText() {
        let result = PiCodingAgentModule.runCLI(argv: ["--help"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .showHelp)
        XCTAssertTrue(result.stdout.contains("Usage:"))
        XCTAssertTrue(result.stdout.contains("--mode <mode>"))
    }

    func testVersionFlagReturnsVersion() {
        let result = PiCodingAgentModule.runCLI(argv: ["--version"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .showVersion)
        XCTAssertTrue(result.stdout.contains("pi-swift"))
    }

    func testDefaultStartupIsInteractive() {
        let result = PiCodingAgentModule.runCLI(argv: ["hello"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startInteractive(prompt: "hello"))
    }

    func testPrintFlagSelectsPrintMode() {
        let result = PiCodingAgentModule.runCLI(argv: ["--print", "hello"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startPrint(prompt: "hello", pipedInput: nil))
    }

    func testPipedStdinForcesPrintMode() {
        let result = PiCodingAgentModule.runCLI(
            argv: [],
            env: .init(executableName: "pi-swift", stdinIsTTY: false, pipedStdin: "stdin text")
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startPrint(prompt: nil, pipedInput: "stdin text"))
    }

    func testRPCModeSelectsRPCStartupAction() {
        let result = PiCodingAgentModule.runCLI(argv: ["--mode", "rpc"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.action, .startRPC)
    }

    func testInvalidModeReturnsUsageError() {
        let result = PiCodingAgentModule.runCLI(argv: ["--mode", "invalid"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.action, .usageError(message: "Invalid mode: invalid. Expected one of: text, rpc"))
        XCTAssertTrue(result.stderr.contains("Invalid mode"))
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }

    func testUnknownFlagReturnsUsageError() {
        let result = PiCodingAgentModule.runCLI(argv: ["--unknown"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.action, .usageError(message: "Unknown option: --unknown"))
    }

    func testArgsParserParsesProviderModelAndPrompt() throws {
        let parsed = try PiCodingAgentCLIArgsParser.parse(["--provider", "openai", "--model", "gpt-5", "hello"])
        XCTAssertEqual(parsed.provider, "openai")
        XCTAssertEqual(parsed.model, "gpt-5")
        XCTAssertEqual(parsed.prompt, "hello")
        XCTAssertFalse(parsed.printMode)
    }
}
