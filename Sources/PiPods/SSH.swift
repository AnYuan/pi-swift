import Foundation

public enum PiPodsSSHError: Error, Equatable, CustomStringConvertible {
    case emptyCommand
    case invalidCommand(String)
    case hostNotFound

    public var description: String {
        switch self {
        case .emptyCommand: return "SSH command is empty"
        case .invalidCommand(let value): return "Invalid SSH command: \(value)"
        case .hostNotFound: return "Could not parse host from SSH command"
        }
    }
}

public struct PiPodsSSHInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct PiPodsSSHCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var host: String
    public var port: String

    public init(executable: String, arguments: [String], host: String, port: String) {
        self.executable = executable
        self.arguments = arguments
        self.host = host
        self.port = port
    }

    public static func parse(_ value: String) throws -> PiPodsSSHCommand {
        let parts = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = parts.first else { throw PiPodsSSHError.emptyCommand }
        guard executable == "ssh" else { throw PiPodsSSHError.invalidCommand(value) }

        var host = ""
        var port = "22"
        var index = 1
        while index < parts.count {
            let part = parts[index]
            if part == "-p", index + 1 < parts.count {
                port = parts[index + 1]
                index += 2
                continue
            }
            if !part.hasPrefix("-") {
                host = part
                break
            }
            index += 1
        }

        guard !host.isEmpty else { throw PiPodsSSHError.hostNotFound }
        return .init(executable: executable, arguments: Array(parts.dropFirst()), host: host, port: port)
    }

    public func execInvocation(
        command: String,
        keepAlive: Bool = false,
        forceTTY: Bool = false
    ) -> PiPodsSSHInvocation {
        var args = arguments
        if forceTTY && !args.contains("-t") {
            args.insert("-t", at: 0)
        }
        if keepAlive {
            args.insert(contentsOf: ["-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=120"], at: 0)
        }
        args.append(command)
        return .init(executable: executable, arguments: args)
    }

    public func scpInvocation(localPath: String, remotePath: String) -> PiPodsSSHInvocation {
        .init(executable: "scp", arguments: ["-P", port, localPath, "\(host):\(remotePath)"])
    }
}
