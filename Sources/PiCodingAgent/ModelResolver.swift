import Foundation
import PiAI

public enum PiCodingAgentThinkingLevel: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public struct PiCodingAgentParsedModelPatternResult: Equatable, Sendable {
    public var model: PiAIModel?
    public var thinkingLevel: PiCodingAgentThinkingLevel?
    public var warning: String?

    public init(model: PiAIModel?, thinkingLevel: PiCodingAgentThinkingLevel?, warning: String?) {
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.warning = warning
    }
}

public struct PiCodingAgentResolveCLIModelResult: Equatable, Sendable {
    public var model: PiAIModel?
    public var thinkingLevel: PiCodingAgentThinkingLevel?
    public var warning: String?
    public var error: String?

    public init(model: PiAIModel?, thinkingLevel: PiCodingAgentThinkingLevel?, warning: String?, error: String?) {
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.warning = warning
        self.error = error
    }
}

public struct PiCodingAgentModelRegistry: Sendable {
    private let registry: PiAIModelRegistry
    private let authStorage: PiCodingAgentAuthStorage?

    public init(models: [PiAIModel], authStorage: PiCodingAgentAuthStorage? = nil) {
        self.registry = .init(models: models)
        self.authStorage = authStorage
    }

    public func getAll() -> [PiAIModel] {
        registry.allModels()
    }

    public func getAvailable() -> [PiAIModel] {
        guard let authStorage else { return registry.allModels() }
        return registry.allModels().filter { authStorage.hasAuth(provider: $0.provider) }
    }

    public func resolve(_ query: String) throws -> PiAIModel {
        try registry.resolve(query)
    }

    public func model(provider: String, id: String) -> PiAIModel? {
        registry.model(provider: provider, id: id)
    }

    public func apiKey(provider: String) async -> String? {
        guard let authStorage else { return nil }
        return await authStorage.apiKey(for: provider)
    }
}

public enum PiCodingAgentModelResolver {
    private static let openAICompatibleProviderAliases = [
        "openai-compatible",
        "openai-compatible-local",
    ]

    public static let defaultModelPerProvider: [String: String] = [
        "anthropic": "claude-sonnet-4-5",
        "openai": "gpt-4o",
        "openai-compatible": "mlx-community/Qwen3.5-35B-A3B-bf16",
        "openai-compatible-local": "mlx-community/Qwen3.5-35B-A3B-bf16",
        "openrouter": "openai/gpt-4o",
        "google": "gemini-2.5-pro",
        "google-vertex": "gemini-2.5-pro",
    ]

    public static func parseModelPattern(
        _ pattern: String,
        availableModels: [PiAIModel],
        allowInvalidThinkingLevelFallback: Bool = true
    ) -> PiCodingAgentParsedModelPatternResult {
        if let exact = tryMatchModel(pattern, availableModels: availableModels) {
            return .init(model: exact, thinkingLevel: nil, warning: nil)
        }

        guard let colonIndex = pattern.lastIndex(of: ":") else {
            return .init(model: nil, thinkingLevel: nil, warning: nil)
        }

        let prefix = String(pattern[..<colonIndex])
        let suffix = String(pattern[pattern.index(after: colonIndex)...])

        if let thinking = PiCodingAgentThinkingLevel(rawValue: suffix) {
            let nested = parseModelPattern(prefix, availableModels: availableModels, allowInvalidThinkingLevelFallback: allowInvalidThinkingLevelFallback)
            if nested.model != nil, nested.warning == nil {
                return .init(model: nested.model, thinkingLevel: thinking, warning: nil)
            }
            return nested
        }

        guard allowInvalidThinkingLevelFallback else {
            return .init(model: nil, thinkingLevel: nil, warning: nil)
        }

        let nested = parseModelPattern(prefix, availableModels: availableModels, allowInvalidThinkingLevelFallback: allowInvalidThinkingLevelFallback)
        guard nested.model != nil else { return nested }
        return .init(
            model: nested.model,
            thinkingLevel: nil,
            warning: "Invalid thinking level \"\(suffix)\" in pattern \"\(pattern)\". Using default instead."
        )
    }

    public static func resolveCLIModel(
        cliProvider: String?,
        cliModel: String?,
        registry: PiCodingAgentModelRegistry
    ) -> PiCodingAgentResolveCLIModelResult {
        guard let cliModel, !cliModel.isEmpty else {
            return .init(model: nil, thinkingLevel: nil, warning: nil, error: nil)
        }

        let models = registry.getAll()
        guard !models.isEmpty else {
            return .init(model: nil, thinkingLevel: nil, warning: nil, error: "No models available.")
        }

        var canonicalProviderMap: [String: String] = [:]
        for model in models where canonicalProviderMap[model.provider.lowercased()] == nil {
            canonicalProviderMap[model.provider.lowercased()] = model.provider
        }
        unifyOpenAICompatibleProviderAliases(in: &canonicalProviderMap)
        let resolvedProvider = cliProvider.flatMap { canonicalProviderMap[$0.lowercased()] }
        if let cliProvider, resolvedProvider == nil {
            return .init(model: nil, thinkingLevel: nil, warning: nil, error: "Unknown provider \"\(cliProvider)\".")
        }

        if resolvedProvider == nil, let exact = exactModelMatch(query: cliModel, models: models) {
            return .init(model: exact, thinkingLevel: nil, warning: nil, error: nil)
        }

        let searchModels = resolvedProvider.map { provider in
            models.filter { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
        } ?? models

        let parsed = parseModelPattern(cliModel, availableModels: searchModels, allowInvalidThinkingLevelFallback: false)
        if let model = parsed.model {
            return .init(model: model, thinkingLevel: parsed.thinkingLevel, warning: parsed.warning, error: nil)
        }

        let fallbackParsed = parseModelPattern(cliModel, availableModels: searchModels, allowInvalidThinkingLevelFallback: true)
        if let model = fallbackParsed.model {
            return .init(model: model, thinkingLevel: fallbackParsed.thinkingLevel, warning: fallbackParsed.warning, error: nil)
        }

        return .init(model: nil, thinkingLevel: nil, warning: nil, error: "No models match pattern \"\(cliModel)\".")
    }

    public static func findInitialModel(
        settings: PiCodingAgentSettingsManager,
        registry: PiCodingAgentModelRegistry
    ) -> PiAIModel? {
        if let defaultModel = settings.getDefaultModel() {
            let resolved = resolveCLIModel(
                cliProvider: settings.getDefaultProvider(),
                cliModel: defaultModel,
                registry: registry
            )
            if let model = resolved.model {
                return model
            }
        }

        if let provider = settings.getDefaultProvider(),
           let localModelID = localOpenAIModelID(provider: provider, settings: settings),
           let localModel = resolveModel(provider: provider, id: localModelID, registry: registry) {
            return localModel
        }

        if let provider = settings.getDefaultProvider(),
           let defaultID = defaultModelPerProvider[provider.lowercased()],
           let model = resolveModel(provider: provider, id: defaultID, registry: registry) {
            return model
        }

        return registry.getAvailable().first ?? registry.getAll().first
    }

    private static func localOpenAIModelID(provider: String, settings: PiCodingAgentSettingsManager) -> String? {
        guard openAICompatibleProviderAliases.contains(provider.lowercased()) else { return nil }
        guard let configured = settings.getLocalOpenAIModelID()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !configured.isEmpty else {
            return nil
        }
        return configured
    }

    private static func resolveModel(provider: String, id: String, registry: PiCodingAgentModelRegistry) -> PiAIModel? {
        if let model = registry.model(provider: provider, id: id) {
            return model
        }

        let normalized = provider.lowercased()
        if normalized == "openai-compatible-local" {
            return registry.model(provider: "openai-compatible", id: id)
        }
        if normalized == "openai-compatible" {
            return registry.model(provider: "openai-compatible-local", id: id)
        }
        return nil
    }

    private static func unifyOpenAICompatibleProviderAliases(in map: inout [String: String]) {
        let canonical = openAICompatibleProviderAliases.compactMap { map[$0] }.first
        guard let canonical else { return }
        for alias in openAICompatibleProviderAliases {
            map[alias] = canonical
        }
    }

    private static func exactModelMatch(query: String, models: [PiAIModel]) -> PiAIModel? {
        let lowered = query.lowercased()
        return models.first {
            $0.id.lowercased() == lowered || $0.qualifiedID.lowercased() == lowered
        }
    }

    private static func tryMatchModel(_ pattern: String, availableModels: [PiAIModel]) -> PiAIModel? {
        if let slash = pattern.firstIndex(of: "/") {
            let provider = String(pattern[..<slash])
            let id = String(pattern[pattern.index(after: slash)...])
            if let providerModel = availableModels.first(where: {
                $0.provider.caseInsensitiveCompare(provider) == .orderedSame &&
                $0.id.caseInsensitiveCompare(id) == .orderedSame
            }) {
                return providerModel
            }
        }

        if let exactID = availableModels.first(where: { $0.id.caseInsensitiveCompare(pattern) == .orderedSame }) {
            return exactID
        }

        let lowered = pattern.lowercased()
        let matches = availableModels.filter {
            $0.id.lowercased().contains(lowered) || $0.displayName.lowercased().contains(lowered)
        }
        guard !matches.isEmpty else { return nil }

        let aliases = matches.filter { isAlias(id: $0.id) }
        let candidates = aliases.isEmpty ? matches : aliases
        return candidates.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedDescending
        }.first
    }

    private static func isAlias(id: String) -> Bool {
        if id.hasSuffix("-latest") { return true }
        return id.range(of: #"-\d{8}$"#, options: .regularExpression) == nil
    }
}
