import XCTest
@testable import PiTUI

final class PiTUIEditorComponentTests: XCTestCase {
    override func tearDown() {
        PiTUIKeys.setKittyProtocolActive(false)
        super.tearDown()
    }

    func testRenderPlacesPromptOnFirstLineAndCursorMarkerAtCursor() {
        let model = PiTUIEditorModel()
        model.setText("hello\nworld")
        model.setCursor(line: 1, colUTF16: 2)
        let editor = PiTUIEditorComponent(model: model, prompt: "> ")

        XCTAssertEqual(editor.render(width: 80), ["> hello", "wo\(PiTUICursor.marker)rld"])
    }

    func testHandleInputSupportsTypingNewlineAndSubmit() {
        let editor = PiTUIEditorComponent()
        var submitted: [String] = []
        editor.onSubmit = { submitted.append($0) }

        editor.handleInput("a")
        PiTUIKeys.setKittyProtocolActive(true)
        editor.handleInput("\n") // shift+enter under kitty mode
        PiTUIKeys.setKittyProtocolActive(false)
        editor.handleInput("b")

        XCTAssertEqual(editor.getText(), "a\nb")

        editor.handleInput("\r") // submit
        XCTAssertEqual(submitted, ["a\nb"])
    }

    func testHandleInputSupportsArrowNavigationAcrossLines() {
        let editor = PiTUIEditorComponent()
        editor.setText("abc\ndef")
        editor.model.setCursor(line: 1, colUTF16: 2)

        editor.handleInput("\u{001B}[A") // up
        XCTAssertEqual(editor.model.cursorPosition, .init(line: 0, colUTF16: 2))
        editor.handleInput("\u{001B}[D") // left
        XCTAssertEqual(editor.model.cursorPosition, .init(line: 0, colUTF16: 1))
        editor.handleInput("\u{001B}[B") // down
        XCTAssertEqual(editor.model.cursorPosition, .init(line: 1, colUTF16: 1))
    }

    func testBackspaceAndUndoFlowThroughEditorComponent() {
        let editor = PiTUIEditorComponent()
        editor.setText("ab")
        editor.model.setCursor(line: 0, colUTF16: 2)

        editor.handleInput("\u{007F}") // backspace
        XCTAssertEqual(editor.getText(), "a")

        editor.handleInput("\u{001A}") // ctrl+z
        XCTAssertEqual(editor.getText(), "ab")
    }

    func testOnChangeFiresOnlyWhenTextChanges() {
        let editor = PiTUIEditorComponent()
        var changes: [String] = []
        editor.onChange = { changes.append($0) }

        editor.handleInput("a")
        editor.handleInput("\u{001B}[D") // move only
        editor.handleInput("b")

        XCTAssertEqual(changes, ["a", "ba"])
    }

    func testIntegratesWithTUIHardwareCursorProjectionOnSecondLine() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 5)
        let tui = PiTUI(terminal: terminal)
        tui.setShowHardwareCursor(true)

        let editor = PiTUIEditorComponent(prompt: "> ")
        editor.setText("ab\ncd")
        editor.model.setCursor(line: 1, colUTF16: 1)
        tui.addChild(editor)
        tui.start()

        XCTAssertEqual(terminal.viewport()[0], "> ab")
        XCTAssertEqual(terminal.viewport()[1], "cd")
        XCTAssertEqual(terminal.cursorPosition, .init(row: 1, column: 1))
    }

    func testHistoryNavigationUpDownRestoresEditorDraft() {
        let editor = PiTUIEditorComponent()
        editor.addToHistory("older")
        editor.addToHistory("newer")
        editor.setText("")

        editor.handleInput("\u{001B}[A") // up
        XCTAssertEqual(editor.getText(), "newer")
        editor.handleInput("\u{001B}[A") // up
        XCTAssertEqual(editor.getText(), "older")
        editor.handleInput("\u{001B}[B") // down
        XCTAssertEqual(editor.getText(), "newer")
        editor.handleInput("\u{001B}[B") // down -> draft
        XCTAssertEqual(editor.getText(), "")
    }

    func testTypingExitsEditorHistoryBrowsingMode() {
        let editor = PiTUIEditorComponent()
        editor.addToHistory("hello")
        editor.setText("")

        editor.handleInput("\u{001B}[A")
        XCTAssertEqual(editor.getText(), "hello")

        editor.handleInput("!")
        XCTAssertEqual(editor.getText(), "hello!")

        editor.handleInput("\u{001B}[B") // not browsing anymore, down should move cursor instead
        XCTAssertEqual(editor.getText(), "hello!")
    }

    func testUpArrowUsesCursorMovementWhenNotOnFirstLine() {
        let editor = PiTUIEditorComponent()
        editor.addToHistory("history")
        editor.setText("line1\nline2")
        editor.model.setCursor(line: 1, colUTF16: 2)

        editor.handleInput("\u{001B}[A")

        XCTAssertEqual(editor.getText(), "line1\nline2")
        XCTAssertEqual(editor.model.cursorPosition, .init(line: 0, colUTF16: 2))
    }
}
