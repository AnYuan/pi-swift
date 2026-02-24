import XCTest
@testable import PiTUI

final class PiTUIEditorModelTests: XCTestCase {
    func testInitialStateIsSingleEmptyLine() {
        let editor = PiTUIEditorModel()
        XCTAssertEqual(editor.lines, [""])
        XCTAssertEqual(editor.cursorPosition.line, 0)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 0)
        XCTAssertEqual(editor.getText(), "")
    }

    func testSetTextNormalizesNewlinesAndMovesCursorToEnd() {
        let editor = PiTUIEditorModel()
        editor.setText("a\r\nb\rc")

        XCTAssertEqual(editor.lines, ["a", "b", "c"])
        XCTAssertEqual(editor.getText(), "a\nb\nc")
        XCTAssertEqual(editor.cursorPosition.line, 2)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 1)
    }

    func testInsertTextAtCursorSupportsMultiLineInsert() {
        let editor = PiTUIEditorModel()
        editor.setText("hello")
        editor.setCursor(line: 0, colUTF16: 2)

        editor.insertTextAtCursor("A\nB")

        XCTAssertEqual(editor.lines, ["heA", "Bllo"])
        XCTAssertEqual(editor.getText(), "heA\nBllo")
        XCTAssertEqual(editor.cursorPosition.line, 1)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 1)
    }

    func testInsertNewlineSplitsCurrentLine() {
        let editor = PiTUIEditorModel()
        editor.setText("hello")
        editor.setCursor(line: 0, colUTF16: 2)

        editor.insertNewline()

        XCTAssertEqual(editor.lines, ["he", "llo"])
        XCTAssertEqual(editor.cursorPosition.line, 1)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 0)
    }

    func testBackspaceDeletesGraphemeAndMergesLines() {
        let editor = PiTUIEditorModel()
        editor.setText("a🙂b")
        editor.setCursor(line: 0, colUTF16: "a🙂".utf16.count)
        editor.backspace()
        XCTAssertEqual(editor.getText(), "ab")
        XCTAssertEqual(editor.cursorPosition.colUTF16, 1)

        editor.setText("abc\ndef")
        editor.setCursor(line: 1, colUTF16: 0)
        editor.backspace()
        XCTAssertEqual(editor.lines, ["abcdef"])
        XCTAssertEqual(editor.cursorPosition.line, 0)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 3)
    }

    func testDeleteForwardDeletesGraphemeAndMergesNextLineAtEol() {
        let editor = PiTUIEditorModel()
        editor.setText("a🙂b")
        editor.setCursor(line: 0, colUTF16: 1)
        editor.deleteForward()
        XCTAssertEqual(editor.getText(), "ab")
        XCTAssertEqual(editor.cursorPosition.colUTF16, 1)

        editor.setText("abc\ndef")
        editor.setCursor(line: 0, colUTF16: 3)
        editor.deleteForward()
        XCTAssertEqual(editor.lines, ["abcdef"])
        XCTAssertEqual(editor.cursorPosition.line, 0)
        XCTAssertEqual(editor.cursorPosition.colUTF16, 3)
    }

    func testCursorLeftRightCrossLineBoundariesAndEmoji() {
        let editor = PiTUIEditorModel()
        editor.setText("a🙂\nxy")
        editor.setCursor(line: 0, colUTF16: "a🙂".utf16.count)

        editor.moveCursorLeft()
        XCTAssertEqual(editor.cursorPosition, .init(line: 0, colUTF16: 1))
        editor.moveCursorRight()
        XCTAssertEqual(editor.cursorPosition, .init(line: 0, colUTF16: 3))
        editor.moveCursorRight()
        XCTAssertEqual(editor.cursorPosition, .init(line: 1, colUTF16: 0))
        editor.moveCursorLeft()
        XCTAssertEqual(editor.cursorPosition, .init(line: 0, colUTF16: 3))
    }

    func testUndoRestoresPreviousEditorSnapshots() {
        let editor = PiTUIEditorModel()
        editor.insertTextAtCursor("hello")
        editor.insertNewline()
        editor.insertTextAtCursor("world")
        XCTAssertEqual(editor.getText(), "hello\nworld")

        editor.undo()
        XCTAssertEqual(editor.getText(), "hello\n")
        editor.undo()
        XCTAssertEqual(editor.getText(), "hello")
        editor.undo()
        XCTAssertEqual(editor.getText(), "")
    }
}
