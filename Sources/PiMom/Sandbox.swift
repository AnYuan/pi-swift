import Foundation

public enum PiMomSandboxConfig: Equatable, Sendable {
    case host
    case docker(container: String)
}

public enum PiMomSandboxParseError: Error, Equatable, CustomStringConvertible {
    case missingDockerContainerName
    case invalidSandboxType(String)

    public var description: String {
        switch self {
        case .missingDockerContainerName:
            return "docker sandbox requires container name (e.g., docker:mom-sandbox)"
        case .invalidSandboxType(let value):
            return "Invalid sandbox type '\(value)'. Use 'host' or 'docker:<container-name>'"
        }
    }
}

public enum PiMomSandboxParser {
    public static func parse(_ value: String) throws -> PiMomSandboxConfig {
        if value == "host" { return .host }
        if value.hasPrefix("docker:") {
            let container = String(value.dropFirst("docker:".count))
            guard !container.isEmpty else { throw PiMomSandboxParseError.missingDockerContainerName }
            return .docker(container: container)
        }
        throw PiMomSandboxParseError.invalidSandboxType(value)
    }
}

public struct PiMomExecOptions: Equatable, Sendable {
    public var timeoutSeconds: TimeInterval?

    public init(timeoutSeconds: TimeInterval? = nil) {
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct PiMomExecResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var code: Int32

    public init(stdout: String, stderr: String, code: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.code = code
    }
}

public protocol PiMomProcessRunning: Sendable {
    func run(executable: String, arguments: [String], options: PiMomExecOptions) throws -> PiMomExecResult
}

public protocol PiMomExecutor: Sendable {
    func exec(_ command: String, options: PiMomExecOptions) throws -> PiMomExecResult
    func workspacePath(forHostPath hostPath: String) -> String
}

public extension PiMomExecutor {
    func exec(_ command: String) throws -> PiMomExecResult {
        try exec(command, options: .init())
    }
}

public final class PiMomHostExecutor: PiMomExecutor, @unchecked Sendable {
    private let runner: any PiMomProcessRunning

    public init(runner: any PiMomProcessRunning = PiMomDefaultProcessRunner()) {
        self.runner = runner
    }

    public func exec(_ command: String, options: PiMomExecOptions = .init()) throws -> PiMomExecResult {
        try runner.run(executable: "/bin/sh", arguments: ["-c", command], options: options)
    }

    public func workspacePath(forHostPath hostPath: String) -> String {
        hostPath
    }
}

public final class PiMomDockerExecutor: PiMomExecutor, @unchecked Sendable {
    public let container: String
    private let runner: any PiMomProcessRunning

    public init(container: String, runner: any PiMomProcessRunning = PiMomDefaultProcessRunner()) {
        self.container = container
        self.runner = runner
    }

    public func exec(_ command: String, options: PiMomExecOptions = .init()) throws -> PiMomExecResult {
        let dockerCommand = "docker exec \(container) sh -c \(shellEscape(command))"
        return try runner.run(executable: "/bin/sh", arguments: ["-c", dockerCommand], options: options)
    }

    public func workspacePath(forHostPath hostPath: String) -> String {
        _ = hostPath
        return "/workspace"
    }
}

public enum PiMomExecutorFactory {
    public static func make(config: PiMomSandboxConfig, runner: (any PiMomProcessRunning)? = nil) -> any PiMomExecutor {
        let runner = runner ?? PiMomDefaultProcessRunner()
        switch config {
        case .host:
            return PiMomHostExecutor(runner: runner)
        case .docker(let container):
            return PiMomDockerExecutor(container: container, runner: runner)
        }
    }
}

public final class PiMomDefaultProcessRunner: PiMomProcessRunning, @unchecked Sendable {
    public init() {}

    public func run(executable: String, arguments: [String], options: PiMomExecOptions) throws -> PiMomExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw NSError(domain: "PiMomProcessRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to spawn process: \(executable)"])
        }

        var timedOut = false
        if let timeout = options.timeoutSeconds, timeout > 0 {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }

        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if timedOut {
            throw NSError(domain: "PiMomProcessRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Command timed out after \(Int(options.timeoutSeconds ?? 0)) seconds"])
        }
        return .init(stdout: stdout, stderr: stderr, code: process.terminationStatus)
    }
}

private func shellEscape(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
