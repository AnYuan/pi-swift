import XCTest
@testable import PiAI

final class PiAIModelRegistryTests: XCTestCase {
    private let registry = PiAIModelRegistry(models: [
        .init(provider: "openai", id: "gpt-4o-mini"),
        .init(provider: "openai", id: "gpt-4.1-mini"),
        .init(provider: "anthropic", id: "claude-sonnet-4"),
        .init(provider: "anthropic", id: "claude-haiku-3.5"),
        .init(provider: "google", id: "gemini-2.5-flash"),
    ])

    func testExactProviderAndModelLookup() {
        let model = registry.model(provider: "OpenAI", id: "GPT-4O-MINI")

        XCTAssertEqual(model?.qualifiedID, "openai/gpt-4o-mini")
    }

    func testResolveReturnsExactProviderQualifiedMatch() throws {
        let model = try registry.resolve("anthropic/claude-sonnet-4")

        XCTAssertEqual(model.qualifiedID, "anthropic/claude-sonnet-4")
    }

    func testWildcardSearchMatchesProviderQualifiedPatterns() {
        let matches = registry.search("openai/*mini")

        XCTAssertEqual(matches.map(\.qualifiedID), [
            "openai/gpt-4.1-mini",
            "openai/gpt-4o-mini",
        ])
    }

    func testFuzzySearchPrefersIdPrefixThenContains() {
        let matches = registry.search("sonnet")

        XCTAssertEqual(matches.first?.qualifiedID, "anthropic/claude-sonnet-4")
    }

    func testResolveThrowsNoMatchesError() {
        XCTAssertThrowsError(try registry.resolve("nonexistent")) { error in
            XCTAssertEqual(error as? PiAIModelRegistryError, .noMatches(query: "nonexistent"))
        }
    }

    func testResolveThrowsAmbiguousErrorForMultipleMatches() {
        XCTAssertThrowsError(try registry.resolve("mini")) { error in
            guard case let .ambiguous(query, matches)? = error as? PiAIModelRegistryError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(query, "mini")
            XCTAssertEqual(matches, [
                "openai/gpt-4.1-mini",
                "openai/gpt-4o-mini",
            ])
        }
    }
}

