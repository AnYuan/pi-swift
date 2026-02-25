import Foundation

public struct PiPodsGPU: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var memory: String

    public init(id: Int, name: String, memory: String) {
        self.id = id
        self.name = name
        self.memory = memory
    }
}

public struct PiPodsModelProcess: Codable, Equatable, Sendable {
    public var model: String
    public var port: Int
    public var gpu: [Int]
    public var pid: Int

    public init(model: String, port: Int, gpu: [Int], pid: Int) {
        self.model = model
        self.port = port
        self.gpu = gpu
        self.pid = pid
    }
}

public struct PiPod: Codable, Equatable, Sendable {
    public var ssh: String
    public var gpus: [PiPodsGPU]
    public var models: [String: PiPodsModelProcess]
    public var modelsPath: String?
    public var vllmVersion: String?

    public init(
        ssh: String,
        gpus: [PiPodsGPU] = [],
        models: [String: PiPodsModelProcess] = [:],
        modelsPath: String? = nil,
        vllmVersion: String? = nil
    ) {
        self.ssh = ssh
        self.gpus = gpus
        self.models = models
        self.modelsPath = modelsPath
        self.vllmVersion = vllmVersion
    }
}

public struct PiPodsConfig: Codable, Equatable, Sendable {
    public var pods: [String: PiPod]
    public var active: String?

    public init(pods: [String: PiPod] = [:], active: String? = nil) {
        self.pods = pods
        self.active = active
    }
}
