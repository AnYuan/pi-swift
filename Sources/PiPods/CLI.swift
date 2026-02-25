import Foundation

public enum PiPodsCLIAction: Equatable, Sendable {
    case showHelp
    case showVersion
    case listPods
    case activatePod(name: String)
    case removePod(name: String)
    case ssh(pod: String?, command: String)
    case start(modelID: String, instanceName: String, options: PiPodsStartModelOptions)
    case stop(instanceName: String?, pod: String?)
    case listModels(pod: String?)
    case logs(instanceName: String, pod: String?)
    case usageError(String)
}

public struct PiPodsCLIResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var action: PiPodsCLIAction

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", action: PiPodsCLIAction) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.action = action
    }
}

public struct PiPodsCLIEnvironment: Equatable, Sendable {
    public var executableName: String
    public var processEnv: [String: String]

    public init(executableName: String = "pi-swift pods", processEnv: [String: String] = ProcessInfo.processInfo.environment) {
        self.executableName = executableName
        self.processEnv = processEnv
    }
}

public struct PiPodsCLIRuntimeResponse: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol PiPodsCLIRuntime: Sendable {
    func run(_ invocation: PiPodsSSHInvocation, streaming: Bool) -> PiPodsCLIRuntimeResponse
}

public final class PiPodsNoopCLIRuntime: PiPodsCLIRuntime, @unchecked Sendable {
    public init() {}
    public func run(_ invocation: PiPodsSSHInvocation, streaming: Bool) -> PiPodsCLIRuntimeResponse {
        _ = invocation
        _ = streaming
        return .init()
    }
}

public enum PiPodsCLIApp {
    public static let versionString = "pi-swift-pods 0.1.0"

    private struct ParseError: Error {
        var message: String
    }

    public static func run(
        argv: [String],
        env: PiPodsCLIEnvironment = .init(),
        configStore: PiPodsConfigStore,
        planner: PiPodsModelLifecyclePlanner,
        runtime: any PiPodsCLIRuntime = PiPodsNoopCLIRuntime()
    ) -> PiPodsCLIResult {
        let parse = parseArgs(argv)
        switch parse {
        case .failure(let error):
            let message = error.message
            return .init(exitCode: 2, stderr: message + "\n\n" + helpText(executableName: env.executableName) + "\n", action: .usageError(message))
        case .success(let action):
            return execute(action: action, env: env, configStore: configStore, planner: planner, runtime: runtime)
        }
    }

    public static func helpText(executableName: String) -> String {
        """
        Usage: \(executableName) [command]

        Commands:
          pods                               List configured pods
          pods active <name>                 Set active pod
          pods remove <name>                 Remove pod from config
          ssh [<pod>] \"<command>\"            Run SSH command on pod
          start <model> --name <name> [opts] Plan/start model on pod
          stop [<name>] [--pod <name>]       Stop one model or all on pod
          list [--pod <name>]                List tracked models on pod
          logs <name> [--pod <name>]         Stream model logs

        Options:
          --pod <name>      Override active pod
          --memory <pct>    GPU memory target (e.g. 90%)
          --context <size>  Context size (e.g. 32k)
          --gpus <count>    GPU count for known models
          --vllm <args...>  Pass remaining args as custom vLLM args
          --help, -h        Show help
          --version, -v     Show version
        """
    }

    private static func parseArgs(_ argv: [String]) -> Result<PiPodsCLIAction, ParseError> {
        if argv.isEmpty || argv[0] == "--help" || argv[0] == "-h" { return .success(.showHelp) }
        if argv[0] == "--version" || argv[0] == "-v" { return .success(.showVersion) }

        if argv[0] == "pods" {
            if argv.count == 1 { return .success(.listPods) }
            if argv.count == 3, argv[1] == "active" { return .success(.activatePod(name: argv[2])) }
            if argv.count == 3, argv[1] == "remove" { return .success(.removePod(name: argv[2])) }
            return .failure(.init(message: "Usage: pods [active <name>|remove <name>]"))
        }

        switch argv[0] {
        case "ssh":
            if argv.count == 2 { return .success(.ssh(pod: nil, command: argv[1])) }
            if argv.count == 3 { return .success(.ssh(pod: argv[1], command: argv[2])) }
            return .failure(.init(message: "Usage: ssh [<pod>] \"<command>\""))

        case "logs":
            guard argv.count >= 2 else { return .failure(.init(message: "Usage: logs <name> [--pod <name>]")) }
            let (pod, rest) = parsePodOverride(Array(argv.dropFirst(2)))
            guard rest.isEmpty else { return .failure(.init(message: "Usage: logs <name> [--pod <name>]")) }
            return .success(.logs(instanceName: argv[1], pod: pod))

        case "list":
            let (pod, rest) = parsePodOverride(Array(argv.dropFirst()))
            guard rest.isEmpty else { return .failure(.init(message: "Usage: list [--pod <name>]")) }
            return .success(.listModels(pod: pod))

        case "stop":
            let args = Array(argv.dropFirst())
            var instanceName: String?
            var tail = args
            if let first = args.first, !first.hasPrefix("-") {
                instanceName = first
                tail = Array(args.dropFirst())
            }
            let (pod, rest) = parsePodOverride(tail)
            guard rest.isEmpty else { return .failure(.init(message: "Usage: stop [<name>] [--pod <name>]")) }
            return .success(.stop(instanceName: instanceName, pod: pod))

        case "start":
            guard argv.count >= 2 else { return .failure(.init(message: "Usage: start <model> --name <name> [options]")) }
            return parseStartArgs(Array(argv.dropFirst()))

        default:
            return .failure(.init(message: "Unknown command: \(argv[0])"))
        }
    }

    private static func parseStartArgs(_ args: [String]) -> Result<PiPodsCLIAction, ParseError> {
        let modelID = args[0]
        var index = 1
        var instanceName: String?
        var options = PiPodsStartModelOptions()

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--name":
                guard index + 1 < args.count else { return .failure(.init(message: "Missing value for --name")) }
                instanceName = args[index + 1]
                index += 2
            case "--pod":
                guard index + 1 < args.count else { return .failure(.init(message: "Missing value for --pod")) }
                options.podOverride = args[index + 1]
                index += 2
            case "--memory":
                guard index + 1 < args.count else { return .failure(.init(message: "Missing value for --memory")) }
                options.memory = args[index + 1]
                index += 2
            case "--context":
                guard index + 1 < args.count else { return .failure(.init(message: "Missing value for --context")) }
                options.context = args[index + 1]
                index += 2
            case "--gpus":
                guard index + 1 < args.count, let count = Int(args[index + 1]), count > 0 else {
                    return .failure(.init(message: "--gpus must be a positive number"))
                }
                options.gpus = count
                index += 2
            case "--vllm":
                options.vllmArgs = Array(args[(index + 1)...])
                index = args.count
            default:
                return .failure(.init(message: "Unknown option: \(arg)"))
            }
        }

        guard let instanceName, !instanceName.isEmpty else { return .failure(.init(message: "Usage: start <model> --name <name> [options]")) }
        return .success(.start(modelID: modelID, instanceName: instanceName, options: options))
    }

    private static func parsePodOverride(_ args: [String]) -> (String?, [String]) {
        guard let idx = args.firstIndex(of: "--pod"), idx + 1 < args.count else { return (nil, args) }
        var rest = args
        let pod = rest[idx + 1]
        rest.removeSubrange(idx...(idx + 1))
        return (pod, rest)
    }

    private static func execute(
        action: PiPodsCLIAction,
        env: PiPodsCLIEnvironment,
        configStore: PiPodsConfigStore,
        planner: PiPodsModelLifecyclePlanner,
        runtime: any PiPodsCLIRuntime
    ) -> PiPodsCLIResult {
        switch action {
        case .showHelp:
            return .init(exitCode: 0, stdout: helpText(executableName: env.executableName) + "\n", action: action)
        case .showVersion:
            return .init(exitCode: 0, stdout: versionString + "\n", action: action)
        case .listPods:
            let config = configStore.load()
            if config.pods.isEmpty {
                return .init(exitCode: 0, stdout: "No pods configured.\n", action: action)
            }
            let lines = config.pods.keys.sorted().map { name in
                let marker = config.active == name ? "*" : " "
                return "\(marker) \(name) - \(config.pods[name]?.ssh ?? "")"
            }
            return .init(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n", action: action)
        case .activatePod(let name):
            do {
                try configStore.setActivePod(name: name)
                return .init(exitCode: 0, stdout: "Activated pod '\(name)'.\n", action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .removePod(let name):
            do {
                try configStore.removePod(name: name)
                return .init(exitCode: 0, stdout: "Removed pod '\(name)'.\n", action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .ssh(let podOverride, let command):
            do {
                let resolved = try planner.resolvePod(podOverride: podOverride)
                let ssh = try PiPodsSSHCommand.parse(resolved.pod.ssh)
                let invocation = ssh.execInvocation(command: command)
                let result = runtime.run(invocation, streaming: true)
                return .init(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .start(let modelID, let instanceName, let options):
            do {
                let plan = try planner.planStart(modelID: modelID, instanceName: instanceName, options: options, env: env.processEnv)
                let resolved = try planner.resolvePod(podOverride: options.podOverride)
                let ssh = try PiPodsSSHCommand.parse(resolved.pod.ssh)
                let invocation = ssh.execInvocation(command: plan.remoteStartCommand, keepAlive: true, forceTTY: true)
                let result = runtime.run(invocation, streaming: false)
                if result.exitCode != 0 {
                    return .init(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, action: action)
                }
                let pid = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                var config = configStore.load()
                guard var pod = config.pods[plan.podName] else {
                    return .init(exitCode: 1, stderr: "Pod disappeared during start planning.\n", action: action)
                }
                pod.models[instanceName] = .init(model: modelID, port: plan.port, gpu: plan.gpuIDs, pid: pid)
                config.pods[plan.podName] = pod
                try configStore.save(config)
                let summary = "Started '\(instanceName)' on '\(plan.podName)' (port \(plan.port), pid \(pid)).\n"
                return .init(exitCode: 0, stdout: summary, action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .stop(let instanceName, let podOverride):
            do {
                let plan = try planner.planStop(instanceName: instanceName, podOverride: podOverride)
                let resolved = try planner.resolvePod(podOverride: podOverride)
                let ssh = try PiPodsSSHCommand.parse(resolved.pod.ssh)
                let result = runtime.run(ssh.execInvocation(command: plan.remoteCommand), streaming: false)
                if result.exitCode == 0 {
                    var config = configStore.load()
                    if var pod = config.pods[plan.podName] {
                        if let instanceName {
                            pod.models.removeValue(forKey: instanceName)
                        } else {
                            pod.models.removeAll()
                        }
                        config.pods[plan.podName] = pod
                        try? configStore.save(config)
                    }
                }
                return .init(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .listModels(let podOverride):
            do {
                let resolved = try planner.resolvePod(podOverride: podOverride)
                let models = resolved.pod.models.keys.sorted()
                let lines = models.map { name in
                    if let process = resolved.pod.models[name] {
                        return "\(name) \(process.model) port=\(process.port) pid=\(process.pid)"
                    }
                    return name
                }
                return .init(exitCode: 0, stdout: (lines.isEmpty ? "(no models)" : lines.joined(separator: "\n")) + "\n", action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .logs(let instanceName, let podOverride):
            do {
                let resolved = try planner.resolvePod(podOverride: podOverride)
                guard resolved.pod.models[instanceName] != nil else {
                    return .init(exitCode: 1, stderr: "Model '\(instanceName)' not found.\n", action: action)
                }
                let ssh = try PiPodsSSHCommand.parse(resolved.pod.ssh)
                let result = runtime.run(ssh.execInvocation(command: "tail -f ~/.vllm_logs/\(instanceName).log", keepAlive: true), streaming: true)
                return .init(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, action: action)
            } catch {
                return .init(exitCode: 1, stderr: "\(error)\n", action: action)
            }
        case .usageError:
            return .init(exitCode: 2, stderr: "Usage error\n", action: action)
        }
    }
}
