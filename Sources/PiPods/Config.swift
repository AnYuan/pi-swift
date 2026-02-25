import Foundation

public enum PiPodsConfigStoreError: Error, Equatable, CustomStringConvertible {
    case podNotFound(String)
    case io(String)

    public var description: String {
        switch self {
        case .podNotFound(let name):
            return "Pod not found: \(name)"
        case .io(let message):
            return "Config I/O error: \(message)"
        }
    }
}

public final class PiPodsConfigStore {
    private let configDirectory: String
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configDirectory: String, fileManager: FileManager = .default) {
        self.configDirectory = configDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public var configPath: String {
        (configDirectory as NSString).appendingPathComponent("pods.json")
    }

    public func load() -> PiPodsConfig {
        guard fileManager.fileExists(atPath: configPath) else { return .init() }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            return try decoder.decode(PiPodsConfig.self, from: data)
        } catch {
            return .init()
        }
    }

    public func save(_ config: PiPodsConfig) throws {
        do {
            try fileManager.createDirectory(atPath: configDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            throw PiPodsConfigStoreError.io("Failed to save config")
        }
    }

    public func getActivePod() -> (name: String, pod: PiPod)? {
        let config = load()
        guard let active = config.active, let pod = config.pods[active] else { return nil }
        return (active, pod)
    }

    public func addPod(name: String, pod: PiPod) throws {
        var config = load()
        config.pods[name] = pod
        if config.active == nil {
            config.active = name
        }
        try save(config)
    }

    public func removePod(name: String) throws {
        var config = load()
        config.pods.removeValue(forKey: name)
        if config.active == name {
            config.active = nil
        }
        try save(config)
    }

    public func setActivePod(name: String) throws {
        var config = load()
        guard config.pods[name] != nil else {
            throw PiPodsConfigStoreError.podNotFound(name)
        }
        config.active = name
        try save(config)
    }
}
