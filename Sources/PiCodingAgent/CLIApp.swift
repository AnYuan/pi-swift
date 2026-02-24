import Foundation

public enum PiCodingAgentStartupAction: Equatable, Sendable {
    case showHelp
    case showVersion
    case startInteractive(prompt: String?)
    case startPrint(prompt: String?, pipedInput: String?)
    case startJSON(prompt: String?, pipedInput: String?)
    case startRPC
    case usageError(message: String)
}

public struct PiCodingAgentCLIResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var action: PiCodingAgentStartupAction

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", action: PiCodingAgentStartupAction) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.action = action
    }
}

public struct PiCodingAgentCLIEnvironment: Equatable, Sendable {
    public var executableName: String
    public var stdinIsTTY: Bool
    public var pipedStdin: String?

    public init(executableName: String = "pi-swift", stdinIsTTY: Bool = true, pipedStdin: String? = nil) {
        self.executableName = executableName
        self.stdinIsTTY = stdinIsTTY
        self.pipedStdin = pipedStdin
    }
}

public enum PiCodingAgentCLIApp {
    public static let versionString = "pi-swift 0.1.0"

    public static func run(argv: [String], env: PiCodingAgentCLIEnvironment = .init()) -> PiCodingAgentCLIResult {
        let parsed: PiCodingAgentCLIArgs
        do {
            parsed = try PiCodingAgentCLIArgsParser.parse(argv)
        } catch let error as PiCodingAgentCLIParseError {
            let help = PiCodingAgentCLIArgsParser.helpText(executableName: env.executableName)
            return .init(
                exitCode: 2,
                stderr: error.description + "\n\n" + help + "\n",
                action: .usageError(message: error.description)
            )
        } catch {
            return .init(exitCode: 2, stderr: "Unknown CLI parse error\n", action: .usageError(message: "Unknown CLI parse error"))
        }

        if parsed.help {
            return .init(
                exitCode: 0,
                stdout: PiCodingAgentCLIArgsParser.helpText(executableName: env.executableName) + "\n",
                action: .showHelp
            )
        }

        if parsed.version {
            return .init(exitCode: 0, stdout: versionString + "\n", action: .showVersion)
        }

        let pipedInput = (env.stdinIsTTY ? nil : env.pipedStdin?.isEmpty == false ? env.pipedStdin : nil)
        let effectivePrint = parsed.printMode || pipedInput != nil

        if parsed.mode == .rpc {
            return .init(exitCode: 0, action: .startRPC)
        }
        if parsed.mode == .json {
            return .init(exitCode: 0, action: .startJSON(prompt: parsed.prompt, pipedInput: pipedInput))
        }

        if effectivePrint {
            return .init(exitCode: 0, action: .startPrint(prompt: parsed.prompt, pipedInput: pipedInput))
        }

        return .init(exitCode: 0, action: .startInteractive(prompt: parsed.prompt))
    }
}
