import Foundation

public enum PiCodingAgentCLIMode: String, CaseIterable, Equatable, Sendable {
    case text
    case rpc
}

public struct PiCodingAgentCLIArgs: Equatable, Sendable {
    public var help: Bool = false
    public var version: Bool = false
    public var printMode: Bool = false
    public var mode: PiCodingAgentCLIMode?
    public var provider: String?
    public var model: String?
    public var prompt: String?

    public init() {}
}

public enum PiCodingAgentCLIParseError: Error, Equatable, CustomStringConvertible {
    case unknownFlag(String)
    case missingValue(String)
    case invalidMode(String)
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case .unknownFlag(let flag):
            return "Unknown option: \(flag)"
        case .missingValue(let flag):
            return "Missing value for option: \(flag)"
        case .invalidMode(let value):
            return "Invalid mode: \(value). Expected one of: text, rpc"
        case .unexpectedArgument(let value):
            return "Unexpected argument: \(value)"
        }
    }
}

public enum PiCodingAgentCLIArgsParser {
    public static func parse(_ argv: [String]) throws -> PiCodingAgentCLIArgs {
        var args = PiCodingAgentCLIArgs()
        var iterator = argv.makeIterator()

        while let token = iterator.next() {
            switch token {
            case "-h", "--help":
                args.help = true
            case "-v", "--version":
                args.version = true
            case "--print":
                args.printMode = true
            case "--provider":
                guard let value = iterator.next() else { throw PiCodingAgentCLIParseError.missingValue(token) }
                args.provider = value
            case "--model":
                guard let value = iterator.next() else { throw PiCodingAgentCLIParseError.missingValue(token) }
                args.model = value
            case "--mode":
                guard let value = iterator.next() else { throw PiCodingAgentCLIParseError.missingValue(token) }
                guard let mode = PiCodingAgentCLIMode(rawValue: value) else {
                    throw PiCodingAgentCLIParseError.invalidMode(value)
                }
                args.mode = mode
            default:
                if token.hasPrefix("-") {
                    throw PiCodingAgentCLIParseError.unknownFlag(token)
                }
                if args.prompt == nil {
                    args.prompt = token
                } else {
                    throw PiCodingAgentCLIParseError.unexpectedArgument(token)
                }
            }
        }

        return args
    }

    public static func helpText(executableName: String = "pi-swift") -> String {
        """
        Usage: \(executableName) [options] [prompt]

        Options:
          -h, --help            Show help
          -v, --version         Show version
              --print           Run in print mode
              --mode <mode>     Startup mode (text|rpc)
              --provider <id>   Provider override
              --model <id>      Model override

        Examples:
          \(executableName) --help
          \(executableName) --print \"Summarize this repo\"
          \(executableName) --mode rpc
        """
    }
}
