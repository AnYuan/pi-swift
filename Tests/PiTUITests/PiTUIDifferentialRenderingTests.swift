import XCTest
@testable import PiTUI

final class PiTUIDifferentialRenderingTests: XCTestCase {
    final class TestComponent: PiTUIComponent {
        var lines: [String] = []

        func render(width: Int) -> [String] {
            lines.map { String($0.prefix(max(0, width))) }
        }

        func invalidate() {}
    }

    func testWidthChangeTriggersFullRedraw() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Line 0", "Line 1", "Line 2"]
        tui.start()

        let initialFullRedraws = tui.fullRedraws
        terminal.resize(columns: 60, rows: 10)
        tui.requestRender()

        XCTAssertGreaterThan(tui.fullRedraws, initialFullRedraws)
    }

    func testClearOnShrinkClearsStaleRows() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        tui.setClearOnShrink(true)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Line 0", "Line 1", "Line 2", "Line 3", "Line 4", "Line 5"]
        tui.start()

        let initialFullRedraws = tui.fullRedraws
        component.lines = ["Line 0", "Line 1"]
        tui.requestRender()

        XCTAssertGreaterThan(tui.fullRedraws, initialFullRedraws)
        let viewport = terminal.viewport()
        XCTAssertTrue(viewport[0].contains("Line 0"))
        XCTAssertTrue(viewport[1].contains("Line 1"))
        XCTAssertEqual(viewport[2].trimmingCharacters(in: .whitespaces), "")
        XCTAssertEqual(viewport[3].trimmingCharacters(in: .whitespaces), "")
    }

    func testDifferentialRenderingUpdatesOnlyChangedMiddleLine() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Header", "Working...", "Footer"]
        tui.start()
        terminal.clearOperationLog()

        component.lines = ["Header", "Working /", "Footer"]
        tui.requestRender()

        let viewport = terminal.viewport()
        XCTAssertTrue(viewport[0].contains("Header"))
        XCTAssertTrue(viewport[1].contains("Working /"))
        XCTAssertTrue(viewport[2].contains("Footer"))

        let writes = terminal.operationLog.compactMap { op -> PiTUIVirtualTerminal.Operation? in
            if case .writeLine = op { return op }
            return nil
        }
        XCTAssertEqual(writes.count, 1, "Only the changed line should be rewritten")
        if case .writeLine(let row, let content) = writes[0] {
            XCTAssertEqual(row, 1)
            XCTAssertEqual(content, "Working /")
        } else {
            XCTFail("Unexpected operation")
        }
    }

    func testHandlesContentToEmptyAndBack() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Line 0", "Line 1", "Line 2"]
        tui.start()

        component.lines = []
        tui.requestRender()

        component.lines = ["New Line 0", "New Line 1"]
        tui.requestRender()

        let viewport = terminal.viewport()
        XCTAssertTrue(viewport[0].contains("New Line 0"))
        XCTAssertTrue(viewport[1].contains("New Line 1"))
    }

    func testShrinkThenLaterLineChangeStillTargetsCorrectRow() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Line 0", "Line 1", "Line 2", "Line 3", "Line 4"]
        tui.start()

        component.lines = ["Line 0", "Line 1", "Line 2"]
        tui.requestRender()
        terminal.clearOperationLog()

        component.lines = ["Line 0", "CHANGED", "Line 2"]
        tui.requestRender()

        let viewport = terminal.viewport()
        XCTAssertTrue(viewport[1].contains("CHANGED"))
        XCTAssertFalse(terminal.operationLog.contains(.writeLine(row: 0, content: "Line 0")))
        XCTAssertFalse(terminal.operationLog.contains(.writeLine(row: 2, content: "Line 2")))
    }
}
