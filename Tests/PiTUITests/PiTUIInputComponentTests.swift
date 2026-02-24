import XCTest
@testable import PiTUI

final class PiTUIInputComponentTests: XCTestCase {
    func testRenderIncludesPromptAndCursorMarkerAtModelCursor() {
        let model = PiTUIInputModel(value: "hello")
        model.setCursorUTF16(2)
        let input = PiTUIInputComponent(model: model, prompt: "> ")

        let rendered = input.render(width: 80)
        XCTAssertEqual(rendered.count, 1)
        XCTAssertEqual(rendered[0], "> he\(PiTUICursor.marker)llo")
    }

    func testHandleInputDelegatesToModelForEditingKeys() {
        let input = PiTUIInputComponent(prompt: "> ")

        input.handleInput("a")
        input.handleInput("b")
        input.handleInput("\u{001B}[D") // left
        input.handleInput("X")

        XCTAssertEqual(input.getValue(), "aXb")
    }

    func testEnterTriggersSubmitCallbackWithoutMutatingText() {
        let input = PiTUIInputComponent()
        input.setValue("submit me")
        var submitted: [String] = []
        input.onSubmit = { submitted.append($0) }

        input.handleInput("\r")

        XCTAssertEqual(submitted, ["submit me"])
        XCTAssertEqual(input.getValue(), "submit me")
    }

    func testEscapeTriggersEscapeCallback() {
        let input = PiTUIInputComponent()
        var escaped = 0
        input.onEscape = { escaped += 1 }

        input.handleInput("\u{001B}")

        XCTAssertEqual(escaped, 1)
    }

    func testIntegratesWithTUIHardwareCursorProjection() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 3)
        let tui = PiTUI(terminal: terminal)
        tui.setShowHardwareCursor(true)

        let input = PiTUIInputComponent(prompt: "> ")
        input.handleInput("a")
        input.handleInput("b")
        tui.addChild(input)
        tui.start()

        XCTAssertEqual(terminal.viewport()[0], "> ab")
        XCTAssertEqual(terminal.cursorPosition, .init(row: 0, column: 4))
    }

    func testHistoryNavigationUpDownRestoresDraft() {
        let input = PiTUIInputComponent()
        input.addToHistory("older")
        input.addToHistory("newer")
        input.setValue("")

        input.handleInput("\u{001B}[A") // up -> newer
        XCTAssertEqual(input.getValue(), "newer")
        input.handleInput("\u{001B}[A") // up -> older
        XCTAssertEqual(input.getValue(), "older")
        input.handleInput("\u{001B}[B") // down -> newer
        XCTAssertEqual(input.getValue(), "newer")
        input.handleInput("\u{001B}[B") // down -> draft ("")
        XCTAssertEqual(input.getValue(), "")
    }

    func testTypingExitsHistoryBrowsingMode() {
        let input = PiTUIInputComponent()
        input.addToHistory("hello")
        input.setValue("")

        input.handleInput("\u{001B}[A")
        XCTAssertEqual(input.getValue(), "hello")

        input.handleInput("!")
        XCTAssertEqual(input.getValue(), "hello!")

        input.handleInput("\u{001B}[B") // should not re-enter or change because browsing exited
        XCTAssertEqual(input.getValue(), "hello!")
    }
}
