import XCTest
@testable import PiTUI

final class PiTUIRenderSchedulingTests: XCTestCase {
    final class TestComponent: PiTUIComponent {
        var lines: [String] = []
        func render(width: Int) -> [String] { lines.map { String($0.prefix(max(0, width))) } }
        func invalidate() {}
    }

    func testRequestRenderCoalescesUntilManualSchedulerFlush() {
        let scheduler = PiTUIManualRenderScheduler()
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal, scheduler: scheduler)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Initial"]
        tui.start()
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertFalse(terminal.operationLog.isEmpty) // start + hideCursor
        terminal.clearOperationLog()

        scheduler.flush()
        XCTAssertFalse(terminal.operationLog.isEmpty)
        terminal.clearOperationLog()

        component.lines = ["Updated"]
        tui.requestRender()
        tui.requestRender()
        tui.requestRender()

        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertTrue(terminal.operationLog.isEmpty)

        scheduler.flush()
        XCTAssertEqual(
            terminal.operationLog,
            [.writeLine(row: 0, content: "Updated")]
        )
    }

    func testResizeCallbackCoalescesWithExplicitRequestBeforeFlush() {
        let scheduler = PiTUIManualRenderScheduler()
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal, scheduler: scheduler)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Line 0"]
        tui.start()
        scheduler.flush()
        terminal.clearOperationLog()

        component.lines = ["Line 0", "Line 1"]
        terminal.resize(columns: 50, rows: 10) // triggers onResize -> requestRender()
        tui.requestRender() // should coalesce with resize-triggered render

        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.flush()
        XCTAssertGreaterThanOrEqual(tui.fullRedraws, 2) // initial render + width-change full redraw
    }

    func testPendingScheduledRenderDoesNotRunAfterStop() {
        let scheduler = PiTUIManualRenderScheduler()
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal, scheduler: scheduler)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["Initial"]
        tui.start()
        XCTAssertEqual(scheduler.pendingCount, 1)

        tui.stop()
        terminal.clearOperationLog()

        scheduler.flush()

        XCTAssertTrue(terminal.operationLog.isEmpty)
        XCTAssertEqual(terminal.viewport(), Array(repeating: "", count: 10))
    }

    func testOldScheduledRenderIsIgnoredAfterStopAndRestart() {
        let scheduler = PiTUIManualRenderScheduler()
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal, scheduler: scheduler)
        let component = TestComponent()
        tui.addChild(component)

        component.lines = ["First session"]
        tui.start()
        XCTAssertEqual(scheduler.pendingCount, 1)

        tui.stop()
        component.lines = ["Second session"]
        tui.start()
        XCTAssertEqual(scheduler.pendingCount, 2) // old pending + new start request
        terminal.clearOperationLog()

        scheduler.flush()

        XCTAssertEqual(terminal.viewport()[0], "Second session")
        XCTAssertEqual(
            terminal.operationLog.filter {
                if case .writeLine = $0 { return true }
                return false
            },
            [.writeLine(row: 0, content: "Second session")]
        )
    }
}
