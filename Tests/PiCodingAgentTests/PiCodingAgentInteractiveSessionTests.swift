import XCTest
import PiAI
import PiTUI
@testable import PiCodingAgent

final class PiCodingAgentInteractiveSessionTests: XCTestCase {
    private func makeSession(terminal: PiTUIVirtualTerminal, scheduler: PiTUIManualRenderScheduler) -> PiCodingAgentInteractiveSession {
        let settings = PiCodingAgentSettingsManager(storage: PiCodingAgentInMemorySettingsStorage())
        settings.setDefaultProvider("openai")
        settings.setDefaultModel("gpt-4o")
        let registry = PiCodingAgentModelRegistry(models: [
            .init(provider: "openai", id: "gpt-4o"),
            .init(provider: "anthropic", id: "claude-sonnet-4-5")
        ])
        let mode = PiCodingAgentInteractiveMode(settings: settings, modelRegistry: registry)
        return PiCodingAgentInteractiveSession(mode: mode, terminal: terminal, scheduler: scheduler)
    }

    func testStartRendersInitialStatusBarToVirtualTerminal() {
        let terminal = PiTUIVirtualTerminal(columns: 100, rows: 8)
        let scheduler = PiTUIManualRenderScheduler()
        let session = makeSession(terminal: terminal, scheduler: scheduler)

        session.start()
        scheduler.flush()

        let viewport = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewport.contains("Model: openai/gpt-4o"))
        XCTAssertTrue(viewport.contains("F2 Settings"))
    }

    func testHandleInputRequestsRenderAndUpdatesViewport() {
        let terminal = PiTUIVirtualTerminal(columns: 100, rows: 10)
        let scheduler = PiTUIManualRenderScheduler()
        let session = makeSession(terminal: terminal, scheduler: scheduler)
        session.start()
        scheduler.flush()

        session.handleInput("h")
        session.handleInput("i")
        session.handleInput("\r")
        scheduler.flush()

        let viewport = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewport.contains("Submitted prompt: hi"))
    }

    func testCtrlSShortcutOpensSettingsOverlayThroughSessionInput() {
        let terminal = PiTUIVirtualTerminal(columns: 100, rows: 12)
        let scheduler = PiTUIManualRenderScheduler()
        let session = makeSession(terminal: terminal, scheduler: scheduler)
        session.start()
        scheduler.flush()

        session.handleInput("\u{0013}") // ctrl+s
        scheduler.flush()

        let viewport = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewport.contains("Settings"))
        XCTAssertTrue(viewport.contains("defaultThinkingLevel"))
    }

    func testCtrlPShortcutOpensModelSelectorThroughSessionInput() {
        let terminal = PiTUIVirtualTerminal(columns: 100, rows: 12)
        let scheduler = PiTUIManualRenderScheduler()
        let session = makeSession(terminal: terminal, scheduler: scheduler)
        session.start()
        scheduler.flush()

        session.handleInput("\u{0010}") // ctrl+p
        scheduler.flush()

        let viewport = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewport.contains("Model Selector"))
        XCTAssertTrue(viewport.contains("openai/gpt-4o"))
    }
}
