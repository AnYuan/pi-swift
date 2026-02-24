import XCTest
import PiAI
@testable import PiCodingAgent

final class PiCodingAgentInteractiveModeTests: XCTestCase {
    private func makeModels() -> [PiAIModel] {
        [
            .init(provider: "anthropic", id: "claude-sonnet-4-5"),
            .init(provider: "openai", id: "gpt-4o"),
            .init(provider: "openrouter", id: "qwen/qwen3-coder:exacto"),
        ]
    }

    func testRenderShowsStatusBarWithCurrentModelAndShortcutHints() {
        let settings = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings.setDefaultProvider("openai")
        settings.setDefaultModel("gpt-4o")
        let mode = PiCodingAgentInteractiveMode(
            settings: settings,
            modelRegistry: .init(models: makeModels())
        )

        let lines = mode.render(width: 120)
        XCTAssertTrue(lines.contains(where: { $0.contains("Model: openai/gpt-4o") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("F2 Settings") && $0.contains("F3 Models") }))
    }

    func testSettingsShortcutTogglesOverlayAndEscapeClosesIt() {
        let mode = PiCodingAgentInteractiveMode(
            settings: .init(storage: PiCodingAgentInMemorySettingsStorage()),
            modelRegistry: .init(models: makeModels())
        )

        XCTAssertEqual(mode.snapshot().overlay, .none)
        mode.handleKeyID("f2")
        XCTAssertEqual(mode.snapshot().overlay, .settings)
        XCTAssertTrue(mode.render(width: 80).contains(where: { $0.contains("Settings") }))

        mode.handleKeyID("escape")
        XCTAssertEqual(mode.snapshot().overlay, .none)
    }

    func testModelSelectorAppliesSelectedModelToSettings() {
        let settings = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings.setDefaultProvider("openai")
        settings.setDefaultModel("gpt-4o")
        let mode = PiCodingAgentInteractiveMode(
            settings: settings,
            modelRegistry: .init(models: makeModels())
        )

        mode.handleKeyID("f3")
        XCTAssertEqual(mode.snapshot().overlay, .modelSelector)
        mode.handleKeyID("down") // from openai -> openrouter in sorted list
        mode.handleKeyID("enter")

        XCTAssertEqual(mode.snapshot().overlay, .none)
        XCTAssertEqual(settings.getDefaultProvider(), "openrouter")
        XCTAssertEqual(settings.getDefaultModel(), "qwen/qwen3-coder:exacto")
        XCTAssertEqual(mode.snapshot().currentModelQualifiedID, "openrouter/qwen/qwen3-coder:exacto")
    }

    func testSubmitAppendsTranscriptAndClearsEditor() {
        let mode = PiCodingAgentInteractiveMode(
            settings: .init(storage: PiCodingAgentInMemorySettingsStorage()),
            modelRegistry: .init(models: makeModels())
        )

        mode.setDraftText("hello from tui")
        mode.handleKeyID("enter")

        let snapshot = mode.snapshot()
        XCTAssertEqual(snapshot.submittedPrompts, ["hello from tui"])
        XCTAssertEqual(snapshot.editorText, "")
        XCTAssertTrue(mode.render(width: 80).contains(where: { $0.contains("Submitted prompt") }))
    }
}
