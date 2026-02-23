import XCTest
import PiCoreTypes
@testable import PiAI

final class PiAIOAuthHelpersTests: XCTestCase {
    func testProviderRegistrySupportsRegisterLookupAndList() {
        var registry = PiAIOAuthProviderRegistry()
        XCTAssertNil(registry.provider(id: "anthropic"))
        XCTAssertEqual(registry.providers().count, 0)

        registry.register(provider: .init(
            id: "anthropic",
            name: "Anthropic",
            refreshToken: { creds in creds },
            apiKey: { creds in creds.access }
        ))

        XCTAssertEqual(registry.providers().map(\.id), ["anthropic"])
        XCTAssertEqual(registry.provider(id: "anthropic")?.name, "Anthropic")
    }

    func testGetOAuthAPIKeyReturnsNilWhenNoCredentialsExist() async throws {
        let service = PiAIOAuthCredentialService(
            registry: .init([
                .init(id: "anthropic", name: "Anthropic", refreshToken: { $0 }, apiKey: { $0.access }),
            ])
        )

        let result = try await service.getOAuthAPIKey(providerID: "anthropic", credentialsByProvider: [:])
        XCTAssertNil(result)
    }

    func testGetOAuthAPIKeyReturnsExistingTokenWhenNotExpired() async throws {
        let clock = TestClock(now: 1_000)
        let refreshCounter = RefreshCounter()
        let service = PiAIOAuthCredentialService(
            registry: .init([
                .init(
                    id: "anthropic",
                    name: "Anthropic",
                    refreshToken: { creds in
                        await refreshCounter.increment()
                        return creds
                    },
                    apiKey: { $0.access }
                ),
            ]),
            now: { await clock.now() }
        )

        let creds = PiAIOAuthCredentials(refresh: "r", access: "a1", expires: 2_000)
        let result = try await service.getOAuthAPIKey(providerID: "anthropic", credentialsByProvider: ["anthropic": creds])

        XCTAssertEqual(result?.apiKey, "a1")
        XCTAssertEqual(result?.newCredentials, creds)
        let refreshCount = await refreshCounter.value()
        XCTAssertEqual(refreshCount, 0)
    }

    func testGetOAuthAPIKeyRefreshesExpiredToken() async throws {
        let service = PiAIOAuthCredentialService(
            registry: .init([
                .init(
                    id: "google-gemini-cli",
                    name: "Google Gemini CLI",
                    refreshToken: { creds in
                        var updated = creds
                        updated.access = "new-access"
                        updated.expires = 9_999
                        updated.extra["projectId"] = JSONValue.string("demo")
                        return updated
                    },
                    apiKey: { creds in
                        let projectID: String
                        if case .string(let value)? = creds.extra["projectId"] {
                            projectID = value
                        } else {
                            projectID = "missing"
                        }
                        return "{\"token\":\"\(creds.access)\",\"projectId\":\"\(projectID)\"}"
                    }
                ),
            ]),
            now: { 2_000 }
        )

        var creds = PiAIOAuthCredentials(refresh: "r", access: "old-access", expires: 2_000)
        creds.extra["projectId"] = JSONValue.string("demo")

        let result = try await service.getOAuthAPIKey(
            providerID: "google-gemini-cli",
            credentialsByProvider: ["google-gemini-cli": creds]
        )

        XCTAssertEqual(result?.newCredentials.access, "new-access")
        XCTAssertEqual(result?.newCredentials.expires, 9_999)
        XCTAssertEqual(result?.apiKey, #"{"token":"new-access","projectId":"demo"}"#)
    }

    func testGetOAuthAPIKeyThrowsForUnknownProvider() async {
        let service = PiAIOAuthCredentialService(registry: .init())

        await XCTAssertThrowsErrorAsync(
            try await service.getOAuthAPIKey(providerID: "missing", credentialsByProvider: [:])
        ) { error in
            XCTAssertEqual(error as? PiAIOAuthError, .unknownProvider("missing"))
        }
    }

    func testGetOAuthAPIKeyWrapsRefreshFailureWithProviderContext() async {
        let service = PiAIOAuthCredentialService(
            registry: .init([
                .init(
                    id: "openai-codex",
                    name: "OpenAI Codex",
                    refreshToken: { _ in throw PiAIOAuthTestError.refreshFailed },
                    apiKey: { $0.access }
                ),
            ]),
            now: { 10 }
        )

        let creds = PiAIOAuthCredentials(refresh: "r", access: "old", expires: 1)

        await XCTAssertThrowsErrorAsync(
            try await service.getOAuthAPIKey(providerID: "openai-codex", credentialsByProvider: ["openai-codex": creds])
        ) { error in
            XCTAssertEqual(error as? PiAIOAuthError, .refreshFailed(providerID: "openai-codex"))
        }
    }

    func testTokenInjectionIntoHeadersSupportsBearerAndCustomHeader() {
        let base = ["Accept": "application/json"]

        let bearer = PiAIAPIKeyInjector.inject(
            apiKey: "token-123",
            intoHeaders: base,
            using: .authorizationBearer
        )
        XCTAssertEqual(bearer["Authorization"], "Bearer token-123")
        XCTAssertEqual(bearer["Accept"], "application/json")

        let custom = PiAIAPIKeyInjector.inject(
            apiKey: "xyz",
            intoHeaders: base,
            using: .header("x-api-key")
        )
        XCTAssertEqual(custom["x-api-key"], "xyz")
        XCTAssertNil(custom["Authorization"])
    }
}

private actor RefreshCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

private actor TestClock {
    private let current: Int64

    init(now: Int64) {
        self.current = now
    }

    func now() -> Int64 { current }
}

private enum PiAIOAuthTestError: Error {
    case refreshFailed
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}
