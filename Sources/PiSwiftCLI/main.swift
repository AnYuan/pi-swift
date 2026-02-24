import Foundation
import Darwin
import PiCodingAgent

let stdinIsTTY = isatty(STDIN_FILENO) != 0
let stdinData = try? FileHandle.standardInput.readToEnd()
let pipedStdin: String?
if !stdinIsTTY, let stdinData, let text = String(data: stdinData, encoding: .utf8), !text.isEmpty {
    pipedStdin = text
} else {
    pipedStdin = nil
}

let env = PiCodingAgentCLIEnvironment(
    executableName: (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "pi-swift",
    stdinIsTTY: stdinIsTTY,
    pipedStdin: pipedStdin
)

let result = PiCodingAgentCLIExecutor.execute(argv: Array(CommandLine.arguments.dropFirst()), env: env)
if !result.stdout.isEmpty {
    FileHandle.standardOutput.write(Data(result.stdout.utf8))
}
if !result.stderr.isEmpty {
    FileHandle.standardError.write(Data(result.stderr.utf8))
}
if result.exitCode != 0 {
    exit(result.exitCode)
}

switch result.action {
case .startInteractive(let prompt):
    let promptSuffix = prompt.map { " prompt=\($0)" } ?? ""
    print("PiCodingAgent interactive mode\(promptSuffix)")
case .startPrint(let prompt, let pipedInput):
    if result.stdout.isEmpty {
        let promptPart = prompt.map { " prompt=\($0)" } ?? ""
        let stdinPart = pipedInput.map { " stdin=\($0)" } ?? ""
        print("PiCodingAgent print mode\(promptPart)\(stdinPart)")
    }
case .startJSON(let prompt, let pipedInput):
    if result.stdout.isEmpty {
        let promptPart = prompt.map { " prompt=\($0)" } ?? ""
        let stdinPart = pipedInput.map { " stdin=\($0)" } ?? ""
        print("PiCodingAgent json mode\(promptPart)\(stdinPart)")
    }
case .startRPC:
    if result.stdout.isEmpty {
        print("PiCodingAgent rpc mode")
    }
case .showHelp, .showVersion, .usageError:
    break
}
