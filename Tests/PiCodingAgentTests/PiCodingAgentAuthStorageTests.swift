import XCTest
import Foundation
import PiAI
@testable import PiCodingAgent

final class PiCodingAgentAuthStorageTests: XCTestCase {
    func testSetGetListAndRemoveCredentials() throws {
        let storage = PiCodingAgentAuthStorage(backend: PiCodingAgentInMemoryAuthStorageBackend())

        storage.set(provider: "openai", credential: .apiKey("sk-openai"))
        storage.set(provider: "anthropic", credential: .apiKey("sk-anthropic"))

        XCTAssertEqual(storage.list().sorted(), ["anthropic", "openai"])
        XCTAssertEqual(storage.get(provider: "openai"), .apiKey("sk-openai"))
        XCTAssertTrue(storage.has(provider: "anthropic"))

        storage.remove(provider: "openai")
        XCTAssertNil(storage.get(provider: "openai"))
        XCTAssertFalse(storage.has(provider: "openai"))
        XCTAssertEqual(storage.list(), ["anthropic"])
    }

    func testAPIKeyResolutionPrefersRuntimeOverrideThenStoredLiteral() async throws {
        let storage = PiCodingAgentAuthStorage(backend: PiCodingAgentInMemoryAuthStorageBackend())
        storage.set(provider: "openai", credential: .apiKey("stored-key"))

        let initial = await storage.apiKey(for: "openai")
        XCTAssertEqual(initial, "stored-key")

        storage.setRuntimeAPIKey(provider: "openai", apiKey: "runtime-key")
        let runtime = await storage.apiKey(for: "openai")
        XCTAssertEqual(runtime, "runtime-key")

        storage.removeRuntimeAPIKey(provider: "openai")
        let afterRemove = await storage.apiKey(for: "openai")
        XCTAssertEqual(afterRemove, "stored-key")
    }

    func testAPIKeyResolutionSupportsEnvVarNameAndCommandValues() async throws {
        let env: @Sendable (String) -> String? = { key in
            key == "TEST_PROVIDER_KEY" ? "env-value" : nil
        }

        let commandRunner: @Sendable (String) -> String? = { command in
            command == "printf 'command-value\\n'" ? "command-value\n" : nil
        }

        let storage = PiCodingAgentAuthStorage(
            backend: PiCodingAgentInMemoryAuthStorageBackend(),
            env: env,
            commandRunner: commandRunner
        )

        storage.set(provider: "env-provider", credential: .apiKey("TEST_PROVIDER_KEY"))
        storage.set(provider: "cmd-provider", credential: .apiKey("!printf 'command-value\\n'"))
        storage.set(provider: "literal-provider", credential: .apiKey("literal-key"))

        let envKey = await storage.apiKey(for: "env-provider")
        let cmdKey = await storage.apiKey(for: "cmd-provider")
        let literalKey = await storage.apiKey(for: "literal-provider")
        XCTAssertEqual(envKey, "env-value")
        XCTAssertEqual(cmdKey, "command-value")
        XCTAssertEqual(literalKey, "literal-key")
    }

    func testOAuthResolutionRefreshesExpiredCredentialsAndPersistsUpdatedToken() async throws {
        var registry = PiAIOAuthProviderRegistry()
        registry.register(provider: .init(
            id: "anthropic",
            name: "Anthropic",
            refreshToken: { creds in
                .init(refresh: creds.refresh, access: "refreshed-access", expires: 5_000)
            },
            apiKey: { creds in creds.access }
        ))

        let oauthService = PiAIOAuthCredentialService(
            registry: registry,
            now: { 2_000 }
        )

        let storage = PiCodingAgentAuthStorage(
            backend: PiCodingAgentInMemoryAuthStorageBackend(),
            oauthService: oauthService
        )
        storage.set(provider: "anthropic", credential: .oauth(.init(
            refresh: "refresh",
            access: "stale-access",
            expires: 1_000
        )))

        let key = await storage.apiKey(for: "anthropic")
        XCTAssertEqual(key, "refreshed-access")
        XCTAssertEqual(storage.get(provider: "anthropic"), .oauth(.init(
            refresh: "refresh",
            access: "refreshed-access",
            expires: 5_000
        )))
    }

    func testHasAuthIncludesFallbackAndProviderDerivedEnvKey() {
        let env: @Sendable (String) -> String? = { key in
            key == "OPENAI_API_KEY" ? "env-openai" : nil
        }
        let storage = PiCodingAgentAuthStorage(
            backend: PiCodingAgentInMemoryAuthStorageBackend(),
            env: env
        )
        storage.setFallbackResolver { provider in
            provider == "custom" ? "fallback-key" : nil
        }

        XCTAssertTrue(storage.hasAuth(provider: "openai"))
        XCTAssertTrue(storage.hasAuth(provider: "custom"))
        XCTAssertFalse(storage.hasAuth(provider: "missing"))
    }
}
