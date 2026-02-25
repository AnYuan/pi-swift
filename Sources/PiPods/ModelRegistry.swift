import Foundation

public struct PiPodsKnownModelConfig: Equatable, Sendable {
    public var gpuCount: Int
    public var gpuTypes: [String]?
    public var args: [String]
    public var env: [String: String]?
    public var notes: String?

    public init(
        gpuCount: Int,
        gpuTypes: [String]? = nil,
        args: [String],
        env: [String: String]? = nil,
        notes: String? = nil
    ) {
        self.gpuCount = gpuCount
        self.gpuTypes = gpuTypes
        self.args = args
        self.env = env
        self.notes = notes
    }
}

public struct PiPodsKnownModel: Equatable, Sendable {
    public var name: String
    public var configs: [PiPodsKnownModelConfig]
    public var notes: String?

    public init(name: String, configs: [PiPodsKnownModelConfig], notes: String? = nil) {
        self.name = name
        self.configs = configs
        self.notes = notes
    }
}

public struct PiPodsResolvedModelConfig: Equatable, Sendable {
    public var args: [String]
    public var env: [String: String]?
    public var notes: String?

    public init(args: [String], env: [String: String]? = nil, notes: String? = nil) {
        self.args = args
        self.env = env
        self.notes = notes
    }
}

public struct PiPodsModelRegistry: Sendable {
    public var models: [String: PiPodsKnownModel]

    public init(models: [String: PiPodsKnownModel] = PiPodsModelRegistry.defaultModels) {
        self.models = models
    }

    public func isKnownModel(_ modelID: String) -> Bool {
        models[modelID] != nil
    }

    public func displayName(for modelID: String) -> String {
        models[modelID]?.name ?? modelID
    }

    public func knownModelIDs() -> [String] {
        models.keys.sorted()
    }

    public func resolveConfig(modelID: String, gpus: [PiPodsGPU], requestedGPUCount: Int) -> PiPodsResolvedModelConfig? {
        guard let model = models[modelID] else { return nil }
        let gpuType = gpus.first?.name.replacingOccurrences(of: "NVIDIA", with: "").trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""

        var best: PiPodsKnownModelConfig?
        for config in model.configs where config.gpuCount == requestedGPUCount {
            if let types = config.gpuTypes, !types.isEmpty {
                let matches = types.contains { type in
                    type.localizedCaseInsensitiveContains(gpuType) || gpuType.localizedCaseInsensitiveContains(type)
                }
                if !matches { continue }
            }
            best = config
            break
        }
        if best == nil {
            best = model.configs.first(where: { $0.gpuCount == requestedGPUCount })
        }
        guard let best else { return nil }
        return .init(args: best.args, env: best.env, notes: best.notes ?? model.notes)
    }

    public static let defaultModels: [String: PiPodsKnownModel] = [
        "qwen3-coder": .init(
            name: "Qwen3 Coder",
            configs: [
                .init(gpuCount: 1, args: ["--tensor-parallel-size", "1", "--gpu-memory-utilization", "0.9"])
            ]
        ),
        "gpt-oss": .init(
            name: "GPT-OSS",
            configs: [
                .init(gpuCount: 1, args: ["--tensor-parallel-size", "1"], env: ["VLLM_ATTENTION_BACKEND": "FLASH_ATTN"])
            ]
        )
    ]
}
