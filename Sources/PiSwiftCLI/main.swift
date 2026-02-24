import Foundation
import Darwin
import PiCodingAgent

let result = PiCodingAgentModule.runCLI(argv: Array(CommandLine.arguments.dropFirst()))
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
    let promptPart = prompt.map { " prompt=\($0)" } ?? ""
    let stdinPart = pipedInput.map { " stdin=\($0)" } ?? ""
    print("PiCodingAgent print mode\(promptPart)\(stdinPart)")
case .startRPC:
    print("PiCodingAgent rpc mode")
case .showHelp, .showVersion, .usageError:
    break
}
