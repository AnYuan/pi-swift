import XCTest
@testable import PiTUI

final class PiTUIInputModelTests: XCTestCase {
    func testInsertAndCursorMovement() {
        let input = PiTUIInputModel()

        input.handleInput("a")
        input.handleInput("b")
        input.handleInput("c")
        XCTAssertEqual(input.value, "abc")
        XCTAssertEqual(input.cursorUTF16, 3)

        input.handleInput("\u{001B}[D") // left
        input.handleInput("X")

        XCTAssertEqual(input.value, "abXc")
        XCTAssertEqual(input.cursorUTF16, 3)
    }

    func testBackspaceAndDeleteForwardAreGraphemeAware() {
        let input = PiTUIInputModel(value: "a🙂b")
        input.setCursorUTF16("a🙂".utf16.count)

        input.backspace()
        XCTAssertEqual(input.value, "ab")
        XCTAssertEqual(input.cursorUTF16, 1)

        input.setValue("a🙂b")
        input.setCursorUTF16(1)
        input.deleteForward()
        XCTAssertEqual(input.value, "ab")
        XCTAssertEqual(input.cursorUTF16, 1)
    }

    func testCursorMovesAcrossEmojiAsSingleStep() {
        let input = PiTUIInputModel(value: "a🙂b")
        input.moveCursorToEnd()
        XCTAssertEqual(input.cursorUTF16, 4)

        input.moveCursorLeft()
        XCTAssertEqual(input.cursorUTF16, 3)
        input.moveCursorLeft()
        XCTAssertEqual(input.cursorUTF16, 1)
        input.moveCursorRight()
        XCTAssertEqual(input.cursorUTF16, 3)
    }

    func testUndoRestoresPreviousSnapshots() {
        let input = PiTUIInputModel()
        input.insertText("hello")
        input.insertText(" world")
        XCTAssertEqual(input.value, "hello world")

        input.undo()
        XCTAssertEqual(input.value, "hello")
        input.undo()
        XCTAssertEqual(input.value, "")
    }

    func testBracketedPasteIsBufferedAcrossChunksAndUndoesAtomically() {
        let input = PiTUIInputModel(value: "prefix ")
        input.moveCursorToEnd()

        input.handleInput("\u{001B}[200~hello")
        XCTAssertEqual(input.value, "prefix ")
        input.handleInput(" world")
        XCTAssertEqual(input.value, "prefix ")
        input.handleInput("\u{001B}[201~")

        XCTAssertEqual(input.value, "prefix hello world")

        input.undo()
        XCTAssertEqual(input.value, "prefix ")
    }

    func testHandleInputSupportsCtrlAAndCtrlEAndDeleteSequence() {
        let input = PiTUIInputModel(value: "abcd")
        input.setCursorUTF16(2)

        input.handleInput("\u{0001}") // ctrl+a
        XCTAssertEqual(input.cursorUTF16, 0)
        input.handleInput("\u{0005}") // ctrl+e
        XCTAssertEqual(input.cursorUTF16, 4)
        input.handleInput("\u{001B}[D")
        XCTAssertEqual(input.cursorUTF16, 3)
        input.handleInput("\u{001B}[3~") // delete
        XCTAssertEqual(input.value, "abc")
    }

    func testControlCharactersAreIgnoredAsTextInput() {
        let input = PiTUIInputModel()
        input.handleInput("\u{0002}") // ctrl+b (movement/control)
        input.handleInput("\u{009B}") // C1 control
        XCTAssertEqual(input.value, "")
    }
}
