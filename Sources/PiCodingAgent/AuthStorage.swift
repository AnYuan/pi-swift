import Foundation
import PiAI
import PiCoreTypes

public enum PiCodingAgentAuthCredential: Codable, Equatable, Sendable {
    case apiKey(String)
    case oauth(PiAIOAuthCredentials)

    private enum CodingKeys: String, CodingKey {
        case type
        case key
        case refresh
        case access
        case expires
        case extra
    }

    private enum Kind: String, Codable {
        case apiKey = "api_key"
        case oauth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .apiKey:
            self = .apiKey(try container.decode(String.self, forKey: .key))
        case .oauth:
            self = .oauth(.init(
                refresh: try container.decode(String.self, forKey: .refresh),
                access: try container.decode(String.self, forKey: .access),
                expires: try container.decode(Int64.self, forKey: .expires),
                extra: try container.decodeIfPresent([String: JSONValue].self, forKey: .extra) ?? [:]
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey(let key):
            try container.encode(Kind.apiKey, forKey: .type)
            try container.encode(key, forKey: .key)
        case .oauth(let creds):
            try container.encode(Kind.oauth, forKey: .type)
            try container.encode(creds.refresh, forKey: .refresh)
            try container.encode(creds.access, forKey: .access)
            try container.encode(creds.expires, forKey: .expires)
            if !creds.extra.isEmpty {
                try container.encode(creds.extra, forKey: .extra)
            }
        }
    }
}

public protocol PiCodingAgentAuthStorageBackend: Sendable {
    func read() throws -> String?
    func write(_ content: String) throws
}

public final class PiCodingAgentInMemoryAuthStorageBackend: PiCodingAgentAuthStorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(value: String? = nil) {
        self.value = value
    }

    public func read() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func write(_ content: String) throws {
        lock.lock()
        defer { lock.unlock() }
        value = content
    }
}

public final class PiCodingAgentFileAuthStorageBackend: PiCodingAgentAuthStorageBackend, @unchecked Sendable {
    private let path: String
    private let lock = NSLock()

    public init(path: String) {
        self.path = path
    }

    public func read() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    public func write(_ content: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let parent = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

public final class PiCodingAgentAuthStorage: @unchecked Sendable {
    public typealias EnvResolver = @Sendable (String) -> String?
    public typealias CommandRunner = @Sendable (String) -> String?
    public typealias FallbackResolver = @Sendable (String) -> String?

    private let backend: PiCodingAgentAuthStorageBackend
    private let env: EnvResolver
    private let commandRunner: CommandRunner
    private let lock = NSLock()

    private var oauthService: PiAIOAuthCredentialService
    private var credentials: [String: PiCodingAgentAuthCredential] = [:]
    private var runtimeAPIKeys: [String: String] = [:]
    private var fallbackResolver: FallbackResolver?

    public init(
        backend: PiCodingAgentAuthStorageBackend,
        oauthService: PiAIOAuthCredentialService = .init(),
        env: @escaping EnvResolver = { ProcessInfo.processInfo.environment[$0] },
        commandRunner: @escaping CommandRunner = PiCodingAgentAuthStorage.defaultCommandRunner
    ) {
        self.backend = backend
        self.oauthService = oauthService
        self.env = env
        self.commandRunner = commandRunner
        self.credentials = (try? Self.load(backend: backend)) ?? [:]
    }

    public func get(provider: String) -> PiCodingAgentAuthCredential? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[provider]
    }

    public func set(provider: String, credential: PiCodingAgentAuthCredential) {
        lock.lock()
        credentials[provider] = credential
        let snapshot = credentials
        lock.unlock()
        try? persist(snapshot)
    }

    public func remove(provider: String) {
        lock.lock()
        credentials.removeValue(forKey: provider)
        let snapshot = credentials
        lock.unlock()
        try? persist(snapshot)
    }

    public func list() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return credentials.keys.sorted()
    }

    public func has(provider: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return credentials[provider] != nil
    }

    public func setRuntimeAPIKey(provider: String, apiKey: String) {
        lock.lock()
        defer { lock.unlock() }
        runtimeAPIKeys[provider] = apiKey
    }

    public func removeRuntimeAPIKey(provider: String) {
        lock.lock()
        defer { lock.unlock() }
        runtimeAPIKeys.removeValue(forKey: provider)
    }

    public func setFallbackResolver(_ resolver: @escaping FallbackResolver) {
        lock.lock()
        defer { lock.unlock() }
        fallbackResolver = resolver
    }

    public func hasAuth(provider: String) -> Bool {
        if runtimeKey(provider: provider) != nil { return true }
        if get(provider: provider) != nil { return true }
        if env(derivedEnvAPIKeyName(provider: provider)) != nil { return true }
        lock.lock()
        let resolver = fallbackResolver
        lock.unlock()
        return resolver?(provider) != nil
    }

    public func apiKey(for provider: String) async -> String? {
        if let runtime = runtimeKey(provider: provider) {
            return runtime
        }

        if let credential = get(provider: provider) {
            switch credential {
            case .apiKey(let value):
                return resolveAPIKeyString(value)
            case .oauth(let oauthCreds):
                let map = [provider: oauthCreds]
                if let resolution = try? await oauthService.getOAuthAPIKey(providerID: provider, credentialsByProvider: map) {
                    let updated = PiCodingAgentAuthCredential.oauth(resolution.newCredentials)
                    set(provider: provider, credential: updated)
                    return resolution.apiKey
                }
                return nil
            }
        }

        if let envValue = env(derivedEnvAPIKeyName(provider: provider)) {
            let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fallbackResolverValue()?(provider)
    }

    private func runtimeKey(provider: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return runtimeAPIKeys[provider]
    }

    private func fallbackResolverValue() -> FallbackResolver? {
        lock.lock()
        defer { lock.unlock() }
        return fallbackResolver
    }

    private func resolveAPIKeyString(_ raw: String) -> String? {
        if raw.hasPrefix("!") {
            let command = String(raw.dropFirst())
            guard let output = commandRunner(command) else { return nil }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let envValue = env(raw) {
            let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return raw
    }

    private func persist(_ data: [String: PiCodingAgentAuthCredential]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        var text = String(decoding: encoded, as: UTF8.self)
        if !text.hasSuffix("\n") { text += "\n" }
        try backend.write(text)
    }

    private static func load(backend: PiCodingAgentAuthStorageBackend) throws -> [String: PiCodingAgentAuthCredential] {
        guard let raw = try backend.read(), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        return try JSONDecoder().decode([String: PiCodingAgentAuthCredential].self, from: Data(raw.utf8))
    }

    private func derivedEnvAPIKeyName(provider: String) -> String {
        let upper = provider.uppercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        return String(upper) + "_API_KEY"
    }

    public static func defaultCommandRunner(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
