import XCTest
import PiAI
@testable import PiCodingAgent

final class PiCodingAgentModelResolverTests: XCTestCase {
    private let models: [PiAIModel] = [
        .init(provider: "anthropic", id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
        .init(provider: "anthropic", id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5 Dated"),
        .init(provider: "openai", id: "gpt-4o", displayName: "GPT-4o"),
        .init(provider: "openai-compatible", id: "mlx-community/Qwen3.5-35B-A3B-bf16", displayName: "Qwen 3.5 35B A3B (MLX)"),
        .init(provider: "openrouter", id: "qwen/qwen3-coder:exacto", displayName: "Qwen Exacto"),
    ]

    func testParseModelPatternSupportsThinkingSuffixAndPrefersAlias() {
        let result = PiCodingAgentModelResolver.parseModelPattern("sonnet:high", availableModels: models)
        XCTAssertEqual(result.model?.provider, "anthropic")
        XCTAssertEqual(result.model?.id, "claude-sonnet-4-5")
        XCTAssertEqual(result.thinkingLevel, .high)
        XCTAssertNil(result.warning)
    }

    func testParseModelPatternSupportsModelIDsContainingColon() {
        let exact = PiCodingAgentModelResolver.parseModelPattern("qwen/qwen3-coder:exacto", availableModels: models)
        XCTAssertEqual(exact.model?.provider, "openrouter")
        XCTAssertEqual(exact.model?.id, "qwen/qwen3-coder:exacto")
        XCTAssertNil(exact.thinkingLevel)

        let withThinking = PiCodingAgentModelResolver.parseModelPattern("qwen/qwen3-coder:exacto:medium", availableModels: models)
        XCTAssertEqual(withThinking.model?.id, "qwen/qwen3-coder:exacto")
        XCTAssertEqual(withThinking.thinkingLevel, .medium)
        XCTAssertNil(withThinking.warning)
    }

    func testParseModelPatternWarnsOnInvalidThinkingSuffixAndFallsBack() {
        let result = PiCodingAgentModelResolver.parseModelPattern("gpt-4o:random", availableModels: models)
        XCTAssertEqual(result.model?.id, "gpt-4o")
        XCTAssertNil(result.thinkingLevel)
        XCTAssertNotNil(result.warning)
        XCTAssertTrue(result.warning?.contains("Invalid thinking level") == true)
    }

    func testResolveCLIModelSupportsExplicitProviderAndProviderSlashModel() {
        let registry = PiCodingAgentModelRegistry(models: models)

        let withProvider = PiCodingAgentModelResolver.resolveCLIModel(
            cliProvider: "openai",
            cliModel: "4o",
            registry: registry
        )
        XCTAssertNil(withProvider.error)
        XCTAssertEqual(withProvider.model?.provider, "openai")
        XCTAssertEqual(withProvider.model?.id, "gpt-4o")

        let providerSlash = PiCodingAgentModelResolver.resolveCLIModel(
            cliProvider: nil,
            cliModel: "openrouter/qwen/qwen3-coder:exacto:high",
            registry: registry
        )
        XCTAssertNil(providerSlash.error)
        XCTAssertEqual(providerSlash.model?.provider, "openrouter")
        XCTAssertEqual(providerSlash.model?.id, "qwen/qwen3-coder:exacto")
        XCTAssertEqual(providerSlash.thinkingLevel, .high)

        let localExplicit = PiCodingAgentModelResolver.resolveCLIModel(
            cliProvider: "openai-compatible-local",
            cliModel: "mlx-community/Qwen3.5-35B-A3B-bf16",
            registry: registry
        )
        XCTAssertNil(localExplicit.error)
        XCTAssertEqual(localExplicit.model?.provider, "openai-compatible")
        XCTAssertEqual(localExplicit.model?.id, "mlx-community/Qwen3.5-35B-A3B-bf16")
    }

    func testResolveCLIModelReturnsUnknownProviderError() {
        let registry = PiCodingAgentModelRegistry(models: models)
        let result = PiCodingAgentModelResolver.resolveCLIModel(
            cliProvider: "missing-provider",
            cliModel: "sonnet",
            registry: registry
        )
        XCTAssertNil(result.model)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error?.contains("Unknown provider") == true)
    }

    func testModelRegistryFiltersAvailableModelsByAuthAndResolvesAPIKey() async {
        let auth = PiCodingAgentAuthStorage(
            backend: PiCodingAgentInMemoryAuthStorageBackend(),
            env: { key in key == "OPENAI_API_KEY" ? "env-openai" : nil }
        )
        auth.set(provider: "anthropic", credential: .apiKey("sk-ant"))
        let registry = PiCodingAgentModelRegistry(models: models, authStorage: auth)

        XCTAssertEqual(Set(registry.getAvailable().map(\.provider)), Set(["anthropic", "openai"]))
        let openAIKey = await registry.apiKey(provider: "openai")
        XCTAssertEqual(openAIKey, "env-openai")
        let anthropicKey = await registry.apiKey(provider: "anthropic")
        XCTAssertEqual(anthropicKey, "sk-ant")
    }

    func testFindInitialModelUsesSettingsThenProviderDefault() {
        let registry = PiCodingAgentModelRegistry(models: models)
        let settings = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings.setDefaultProvider("openai")
        settings.setDefaultModel("gpt-4o")

        let initial = PiCodingAgentModelResolver.findInitialModel(settings: settings, registry: registry)
        XCTAssertEqual(initial?.qualifiedID, "openai/gpt-4o")

        let settings2 = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings2.setDefaultProvider("anthropic")
        let initial2 = PiCodingAgentModelResolver.findInitialModel(settings: settings2, registry: registry)
        XCTAssertEqual(initial2?.qualifiedID, "anthropic/claude-sonnet-4-5")

        let settings3 = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings3.setDefaultProvider("openai-compatible")
        let initial3 = PiCodingAgentModelResolver.findInitialModel(settings: settings3, registry: registry)
        XCTAssertEqual(initial3?.qualifiedID, "openai-compatible/mlx-community/Qwen3.5-35B-A3B-bf16")

        let settings4 = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings4.setDefaultProvider("openai-compatible-local")
        settings4.setLocalOpenAIModelID("mlx-community/Qwen3.5-35B-A3B-bf16")
        let initial4 = PiCodingAgentModelResolver.findInitialModel(settings: settings4, registry: registry)
        XCTAssertEqual(initial4?.qualifiedID, "openai-compatible/mlx-community/Qwen3.5-35B-A3B-bf16")
    }
}
