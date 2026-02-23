import XCTest
@testable import PiTUI

final class PiTUICursorTests: XCTestCase {
    final class CursorComponent: PiTUIComponent {
        var lines: [String] = []
        func render(width: Int) -> [String] { lines.map { String($0.prefix(max(0, width))) } }
        func invalidate() {}
    }

    func testCursorMarkerIsRemovedFromRenderedLinesAndCursorIsPositioned() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = CursorComponent()
        tui.addChild(component)
        tui.setShowHardwareCursor(true)

        component.lines = [
            "Header",
            "ab\(PiTUICursor.marker)cd"
        ]

        tui.start()

        let viewport = terminal.viewport()
        XCTAssertEqual(viewport[1], "abcd")
        XCTAssertEqual(terminal.cursorPosition, .init(row: 1, column: 2))
        XCTAssertTrue(terminal.operationLog.contains(.showCursor))
    }

    func testCursorColumnUsesVisibleWidthBeforeMarkerIgnoringANSISequences() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = CursorComponent()
        tui.addChild(component)
        tui.setShowHardwareCursor(true)

        component.lines = [
            "\u{001B}[31mAB\u{001B}[0m\(PiTUICursor.marker)Z"
        ]

        tui.start()

        XCTAssertEqual(terminal.cursorPosition, .init(row: 0, column: 2))
        XCTAssertEqual(terminal.viewport()[0], "\u{001B}[31mAB\u{001B}[0mZ\u{001B}[0m")
    }

    func testNoCursorMarkerKeepsCursorHidden() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = CursorComponent()
        tui.addChild(component)
        tui.setShowHardwareCursor(true)

        component.lines = ["No cursor here"]
        tui.start()

        XCTAssertNil(terminal.cursorPosition)
    }

    func testCursorColumnCountsWideCharactersUsingDisplayWidth() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = CursorComponent()
        tui.addChild(component)
        tui.setShowHardwareCursor(true)

        component.lines = ["你\(PiTUICursor.marker)A"]
        tui.start()

        XCTAssertEqual(terminal.cursorPosition, .init(row: 0, column: 2))
    }
}
