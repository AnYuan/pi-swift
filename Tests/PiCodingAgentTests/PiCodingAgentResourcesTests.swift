import XCTest
import PiTestSupport
@testable import PiCodingAgent

final class PiCodingAgentResourcesTests: XCTestCase {
    private var fixtureLoader: FixtureLoader!
    private var resourcesRoot: String!

    override func setUpWithError() throws {
        fixtureLoader = try FixtureLoader(callerFilePath: #filePath)
        resourcesRoot = fixtureLoader.fixtureURL("pi-coding-agent/resources").path
    }

    func testFrontmatterParserParsesAttributesAndBody() {
        let markdown = """
        ---
        name: demo
        description: test
        ---
        Body line 1
        Body line 2
        """

        let document = PiCodingAgentFrontmatterParser.parse(markdown)
        XCTAssertEqual(document.attributes["name"], "demo")
        XCTAssertEqual(document.attributes["description"], "test")
        XCTAssertEqual(document.body, "Body line 1\nBody line 2")
    }

    func testFrontmatterParserFallsBackWhenFenceIsUnclosed() {
        let markdown = """
        ---
        name: broken
        Body
        """
        let document = PiCodingAgentFrontmatterParser.parse(markdown)
        XCTAssertTrue(document.attributes.isEmpty)
        XCTAssertEqual(document.body, markdown)
    }

    func testPromptArgParsingAndSubstitution() {
        let args = PiCodingAgentResourceLoader.parseCommandArgs(#"one "two words" three\ four"#)
        XCTAssertEqual(args, ["one", "two words", "three four"])

        let rendered = PiCodingAgentResourceLoader.substitutePromptArgs(
            template: "a=$1 all=$@ tail=${@:2}",
            args: ["first", "second", "third"]
        )
        XCTAssertEqual(rendered, "a=first all=first second third tail=second third")
    }

    func testLoadSkillsReportsInvalidAndDuplicateEntries() {
        let loader = PiCodingAgentResourceLoader()
        let loaded = loader.load(paths: .init(
            skillPaths: [(resourcesRoot as NSString).appendingPathComponent("skills")]
        ))

        XCTAssertEqual(loaded.skills.map(\.name), ["alpha-skill"])
        XCTAssertEqual(loaded.skills.first?.description, "Valid alpha skill")
        XCTAssertEqual(loaded.skills.first?.disableModelInvocation, true)

        let warningMessages = loaded.diagnostics
            .filter { $0.resourceType == .skill }
            .map(\.message)

        XCTAssertTrue(warningMessages.contains(where: { $0.contains("Duplicate skill 'alpha-skill'") }))
        XCTAssertTrue(warningMessages.contains(where: { $0.contains("Invalid skill name") }))
        XCTAssertTrue(warningMessages.contains(where: { $0.contains("Skill description is required") }))
    }

    func testLoadPromptsUsesDescriptionFallbackAndDedupesByFilename() {
        let loader = PiCodingAgentResourceLoader()
        let promptsRoot = (resourcesRoot as NSString).appendingPathComponent("prompts")
        let loaded = loader.load(paths: .init(
            promptPaths: [
                (promptsRoot as NSString).appendingPathComponent("core"),
                (promptsRoot as NSString).appendingPathComponent("dupe-a"),
                (promptsRoot as NSString).appendingPathComponent("dupe-b"),
            ]
        ))

        XCTAssertEqual(loaded.prompts.count, 3)
        XCTAssertEqual(Set(loaded.prompts.map(\.name)), Set(["commit", "fallback", "duplicate"]))

        let fallback = try? XCTUnwrap(loaded.prompts.first(where: { $0.name == "fallback" }))
        XCTAssertNotNil(fallback)
        if let fallback {
            let source = "This is a very long first line that should be truncated to sixty characters when used as prompt template description fallback behavior."
            let expected = String(source.prefix(60))
            XCTAssertEqual(fallback.description, expected)
        }

        let promptWarnings = loaded.diagnostics
            .filter { $0.resourceType == .prompt }
            .map(\.message)
        XCTAssertTrue(promptWarnings.contains(where: { $0.contains("Duplicate prompt 'duplicate'") }))
    }

    func testLoadThemesValidatesRequiredColorsAndDedupesByName() {
        let loader = PiCodingAgentResourceLoader()
        let loaded = loader.load(paths: .init(
            themePaths: [(resourcesRoot as NSString).appendingPathComponent("themes")]
        ))

        XCTAssertEqual(loaded.themes.count, 1)
        XCTAssertEqual(loaded.themes.first?.name, "solarized")
        XCTAssertNotNil(loaded.themes.first?.colors["text"])
        XCTAssertNotNil(loaded.themes.first?.colors["background"])

        let themeWarnings = loaded.diagnostics
            .filter { $0.resourceType == .theme }
            .map(\.message)
        XCTAssertTrue(themeWarnings.contains(where: { $0.contains("Theme missing required color 'background'") }))
        XCTAssertTrue(themeWarnings.contains(where: { $0.contains("Duplicate theme 'solarized'") }))
    }

    func testLoadExtensionsDiscoversStandaloneAndPackageEntriesAndRejectsConflicts() {
        let loader = PiCodingAgentResourceLoader()
        let loaded = loader.load(paths: .init(
            extensionPaths: [(resourcesRoot as NSString).appendingPathComponent("extensions")]
        ))

        XCTAssertEqual(Set(loaded.extensions.map(\.name)), Set(["echo", "indexed", "pkg-meta", "pkg-conflict"]))

        let package = try? XCTUnwrap(loaded.extensions.first(where: { $0.name == "pkg-meta" }))
        XCTAssertNotNil(package)
        if let package {
            XCTAssertEqual(package.tools, ["tool-meta"])
            XCTAssertEqual(package.commands, ["cmd-meta"])
            XCTAssertEqual(package.flags, ["--meta"])
            XCTAssertEqual(package.entryPaths.count, 1)
            XCTAssertTrue(package.entryPaths[0].hasSuffix("/pkg-meta/dist/main.js"))
            XCTAssertEqual(package.skillsPaths.count, 1)
            XCTAssertTrue(package.skillsPaths[0].hasSuffix("/pkg-meta/skills"))
        }

        let extensionDiagnostics = loaded.diagnostics
            .filter { $0.resourceType == .extension }
            .map(\.message)
        XCTAssertTrue(extensionDiagnostics.contains(where: { $0.contains("Tool conflict 'tool-alpha'") }))
        XCTAssertTrue(extensionDiagnostics.contains(where: { $0.contains("Failed to parse package.json") }))
    }
}
