import Foundation

public enum PiPodsPlannerError: Error, Equatable, CustomStringConvertible {
    case noActivePod
    case podNotFound(String)
    case missingModelsPath(String)
    case modelAlreadyExists(String)
    case invalidGPUCount(requested: Int, available: Int)
    case unsupportedGPUOverrideForUnknownModel
    case noCompatibleKnownModelConfig(String, Int)

    public var description: String {
        switch self {
        case .noActivePod:
            return "No active pod configured"
        case .podNotFound(let name):
            return "Pod not found: \(name)"
        case .missingModelsPath(let podName):
            return "Pod '\(podName)' does not have a models path configured"
        case .modelAlreadyExists(let name):
            return "Model '\(name)' already exists"
        case .invalidGPUCount(let requested, let available):
            return "Requested \(requested) GPUs but pod only has \(available)"
        case .unsupportedGPUOverrideForUnknownModel:
            return "--gpus is only supported for known models"
        case .noCompatibleKnownModelConfig(let modelID, let count):
            return "No compatible config for \(modelID) using \(count) GPU(s)"
        }
    }
}

public struct PiPodsStartModelOptions: Equatable, Sendable {
    public var podOverride: String?
    public var vllmArgs: [String]
    public var memory: String?
    public var context: String?
    public var gpus: Int?

    public init(
        podOverride: String? = nil,
        vllmArgs: [String] = [],
        memory: String? = nil,
        context: String? = nil,
        gpus: Int? = nil
    ) {
        self.podOverride = podOverride
        self.vllmArgs = vllmArgs
        self.memory = memory
        self.context = context
        self.gpus = gpus
    }
}

public struct PiPodsStartModelPlan: Equatable, Sendable {
    public var podName: String
    public var modelID: String
    public var instanceName: String
    public var port: Int
    public var gpuIDs: [Int]
    public var vllmArgs: [String]
    public var envExports: [String: String]
    public var remoteStartCommand: String
    public var logsCommand: String

    public init(
        podName: String,
        modelID: String,
        instanceName: String,
        port: Int,
        gpuIDs: [Int],
        vllmArgs: [String],
        envExports: [String: String],
        remoteStartCommand: String,
        logsCommand: String
    ) {
        self.podName = podName
        self.modelID = modelID
        self.instanceName = instanceName
        self.port = port
        self.gpuIDs = gpuIDs
        self.vllmArgs = vllmArgs
        self.envExports = envExports
        self.remoteStartCommand = remoteStartCommand
        self.logsCommand = logsCommand
    }
}

public struct PiPodsStopModelPlan: Equatable, Sendable {
    public var podName: String
    public var instanceName: String?
    public var remoteCommand: String

    public init(podName: String, instanceName: String?, remoteCommand: String) {
        self.podName = podName
        self.instanceName = instanceName
        self.remoteCommand = remoteCommand
    }
}

public final class PiPodsModelLifecyclePlanner {
    private let configStore: PiPodsConfigStore
    private let modelRegistry: PiPodsModelRegistry

    public init(configStore: PiPodsConfigStore, modelRegistry: PiPodsModelRegistry = .init()) {
        self.configStore = configStore
        self.modelRegistry = modelRegistry
    }

    public func resolvePod(podOverride: String?) throws -> (name: String, pod: PiPod) {
        let config = configStore.load()
        if let podOverride {
            guard let pod = config.pods[podOverride] else { throw PiPodsPlannerError.podNotFound(podOverride) }
            return (podOverride, pod)
        }
        guard let active = config.active, let pod = config.pods[active] else {
            throw PiPodsPlannerError.noActivePod
        }
        return (active, pod)
    }

    public func nextPort(for pod: PiPod) -> Int {
        let used = Set(pod.models.values.map(\.port))
        var port = 8001
        while used.contains(port) { port += 1 }
        return port
    }

    public func selectGPUs(for pod: PiPod, count: Int = 1) -> [Int] {
        if count >= pod.gpus.count { return pod.gpus.map(\.id) }
        var usage = Dictionary(uniqueKeysWithValues: pod.gpus.map { ($0.id, 0) })
        for model in pod.models.values {
            for gpu in model.gpu {
                usage[gpu, default: 0] += 1
            }
        }
        return usage.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }
        .map(\.key)
        .prefix(count)
        .map { $0 }
    }

    public func planStart(
        modelID: String,
        instanceName: String,
        options: PiPodsStartModelOptions,
        env: [String: String]
    ) throws -> PiPodsStartModelPlan {
        let (podName, pod) = try resolvePod(podOverride: options.podOverride)
        guard let modelsPath = pod.modelsPath, !modelsPath.isEmpty else {
            throw PiPodsPlannerError.missingModelsPath(podName)
        }
        if pod.models[instanceName] != nil {
            throw PiPodsPlannerError.modelAlreadyExists(instanceName)
        }

        let port = nextPort(for: pod)
        let requestedGPUCount = options.gpus
        if let requestedGPUCount, requestedGPUCount > pod.gpus.count {
            throw PiPodsPlannerError.invalidGPUCount(requested: requestedGPUCount, available: pod.gpus.count)
        }

        var gpuIDs: [Int] = []
        var vllmArgs = options.vllmArgs
        var envExports: [String: String] = [
            "HF_HUB_ENABLE_HF_TRANSFER": "1",
            "VLLM_NO_USAGE_STATS": "1",
            "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True",
            "FORCE_COLOR": "1",
            "TERM": "xterm-256color",
        ]
        if let hf = env["HF_TOKEN"] { envExports["HF_TOKEN"] = hf }
        if let apiKey = env["PI_API_KEY"] { envExports["PI_API_KEY"] = apiKey }

        if vllmArgs.isEmpty {
            if modelRegistry.isKnownModel(modelID) {
                let count = requestedGPUCount ?? max(1, min(pod.gpus.count, 1))
                guard let resolved = modelRegistry.resolveConfig(modelID: modelID, gpus: pod.gpus, requestedGPUCount: count) else {
                    throw PiPodsPlannerError.noCompatibleKnownModelConfig(modelID, count)
                }
                gpuIDs = selectGPUs(for: pod, count: count)
                vllmArgs = resolved.args
                for (key, value) in resolved.env ?? [:] { envExports[key] = value }
            } else {
                if requestedGPUCount != nil {
                    throw PiPodsPlannerError.unsupportedGPUOverrideForUnknownModel
                }
                gpuIDs = selectGPUs(for: pod, count: 1)
            }

            if let memory = options.memory {
                let fraction = String(parseMemoryFraction(memory))
                vllmArgs = filteredArgs(vllmArgs, removingFlag: "--gpu-memory-utilization")
                vllmArgs.append(contentsOf: ["--gpu-memory-utilization", fraction])
            }
            if let context = options.context {
                let maxTokens = parseContextSize(context)
                vllmArgs = filteredArgs(vllmArgs, removingFlag: "--max-model-len")
                vllmArgs.append(contentsOf: ["--max-model-len", String(maxTokens)])
            }
        }

        if gpuIDs.count == 1, let first = gpuIDs.first {
            envExports["CUDA_VISIBLE_DEVICES"] = String(first)
        }

        let exports = envExports.keys.sorted().compactMap { key in
            envExports[key].map { "export \(key)=\(shellQuote($0))" }
        }.joined(separator: "\n")
        let commandLineArgs = vllmArgs.map(shellQuote).joined(separator: " ")
        let remoteStartCommand = """
        \(exports)
        mkdir -p ~/.vllm_logs
        MODEL_ID=\(shellQuote(modelID))
        MODEL_NAME=\(shellQuote(instanceName))
        MODEL_PORT=\(port)
        MODELS_PATH=\(shellQuote(modelsPath))
        VLLM_ARGS=\(shellQuote(commandLineArgs))
        setsid sh -lc 'echo "starting $MODEL_NAME on $MODEL_PORT"; echo "$MODEL_ID $VLLM_ARGS" >> ~/.vllm_logs/'"'"'$MODEL_NAME'"'"'.log'
        """

        return .init(
            podName: podName,
            modelID: modelID,
            instanceName: instanceName,
            port: port,
            gpuIDs: gpuIDs,
            vllmArgs: vllmArgs,
            envExports: envExports,
            remoteStartCommand: remoteStartCommand,
            logsCommand: "tail -f ~/.vllm_logs/\(instanceName).log"
        )
    }

    public func planStop(instanceName: String?, podOverride: String?) throws -> PiPodsStopModelPlan {
        let (podName, pod) = try resolvePod(podOverride: podOverride)
        if let instanceName {
            guard let process = pod.models[instanceName] else { throw PiPodsPlannerError.modelAlreadyExists(instanceName) }
            return .init(podName: podName, instanceName: instanceName, remoteCommand: "kill \(process.pid)")
        }
        let pids = pod.models.values.map(\.pid).sorted()
        let command = pids.isEmpty ? "true" : "kill " + pids.map(String.init).joined(separator: " ")
        return .init(podName: podName, instanceName: nil, remoteCommand: command)
    }

    private func parseMemoryFraction(_ value: String) -> Double {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasSuffix("%"), let percent = Double(raw.dropLast()) {
            return percent / 100.0
        }
        return Double(raw) ?? 0.9
    }

    private func parseContextSize(_ value: String) -> Int {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: Int] = [
            "4k": 4096,
            "8k": 8192,
            "16k": 16384,
            "32k": 32768,
            "64k": 65536,
            "128k": 131072,
        ]
        if let mapped = map[normalized] { return mapped }
        return Int(normalized) ?? 8192
    }

    private func filteredArgs(_ args: [String], removingFlag flag: String) -> [String] {
        var result: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if arg == flag {
                skipNext = true
                continue
            }
            result.append(arg)
        }
        return result
    }
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
