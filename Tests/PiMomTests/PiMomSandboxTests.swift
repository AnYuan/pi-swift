import XCTest
@testable import PiMom

final class PiMomSandboxTests: XCTestCase {
    func testParsesHostSandbox() throws {
        XCTAssertEqual(try PiMomSandboxParser.parse("host"), .host)
    }

    func testParsesDockerSandboxWithContainerName() throws {
        XCTAssertEqual(try PiMomSandboxParser.parse("docker:mom-sandbox"), .docker(container: "mom-sandbox"))
    }

    func testParseRejectsEmptyDockerContainerName() {
        XCTAssertThrowsError(try PiMomSandboxParser.parse("docker:")) { error in
            XCTAssertEqual(error as? PiMomSandboxParseError, .missingDockerContainerName)
        }
    }

    func testParseRejectsInvalidSandboxType() {
        XCTAssertThrowsError(try PiMomSandboxParser.parse("podman:box")) { error in
            XCTAssertEqual(error as? PiMomSandboxParseError, .invalidSandboxType("podman:box"))
        }
    }

    func testHostExecutorUsesHostWorkspacePathAndDirectShellCommand() throws {
        let runner = RecordingRunner()
        let executor = PiMomHostExecutor(runner: runner)

        let result = try executor.exec("printf 'hello'")

        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(executor.workspacePath(forHostPath: "/tmp/work"), "/tmp/work")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "/bin/sh")
        XCTAssertEqual(runner.calls[0].arguments, ["-c", "printf 'hello'"])
    }

    func testDockerExecutorWrapsCommandWithDockerExecAndEscapesSingleQuotes() throws {
        let runner = RecordingRunner()
        let executor = PiMomDockerExecutor(container: "mom-box", runner: runner)

        _ = try executor.exec("printf 'hi'")

        XCTAssertEqual(executor.workspacePath(forHostPath: "/Users/anyuan/work"), "/workspace")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "/bin/sh")
        XCTAssertEqual(runner.calls[0].arguments.count, 2)
        XCTAssertEqual(runner.calls[0].arguments[0], "-c")
        XCTAssertTrue(runner.calls[0].arguments[1].contains("docker exec mom-box sh -c"))
        XCTAssertTrue(runner.calls[0].arguments[1].contains("'printf '\\''hi'\\'''"))
    }
}

private final class RecordingRunner: PiMomProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private(set) var calls: [Call] = []

    func run(executable: String, arguments: [String], options: PiMomExecOptions) throws -> PiMomExecResult {
        calls.append(.init(executable: executable, arguments: arguments))
        return .init(stdout: "", stderr: "", code: 0)
    }
}
