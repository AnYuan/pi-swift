import XCTest
@testable import PiTUI

final class PiTUIOverlayCompositionTests: XCTestCase {
    final class EmptyComponent: PiTUIComponent {
        func render(width: Int) -> [String] { [] }
        func invalidate() {}
    }

    final class StaticOverlayComponent: PiTUIComponent {
        var lines: [String]
        private(set) var requestedWidths: [Int] = []

        init(lines: [String]) {
            self.lines = lines
        }

        func render(width: Int) -> [String] {
            requestedWidths.append(width)
            return lines
        }

        func invalidate() {}
    }

    final class StyledContent: PiTUIComponent {
        func render(width: Int) -> [String] {
            let line = "\u{001B}[31m" + String(repeating: "X", count: max(1, width)) + "\u{001B}[0m"
            return [line, line, line]
        }

        func invalidate() {}
    }

    func testOverlayRendersWithResolvedWidthPercentage() {
        let terminal = PiTUIVirtualTerminal(columns: 100, rows: 20)
        let tui = PiTUI(terminal: terminal)
        tui.addChild(EmptyComponent())
        let overlay = StaticOverlayComponent(lines: ["hello"])

        tui.showOverlay(overlay, options: .init(width: .percent(50)))
        tui.start()

        XCTAssertEqual(overlay.requestedWidths.last, 50)
        XCTAssertTrue(terminal.viewport().joined(separator: "\n").contains("hello"))
    }

    func testLaterOverlayRendersOnTopAndHideRestoresPrevious() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 8)
        let tui = PiTUI(terminal: terminal)
        tui.addChild(EmptyComponent())

        let first = StaticOverlayComponent(lines: ["FIRST"])
        let second = StaticOverlayComponent(lines: ["SECOND"])
        tui.showOverlay(first, options: .init(width: .absolute(10), anchor: .topLeft))
        tui.showOverlay(second, options: .init(width: .absolute(10), anchor: .topLeft))
        tui.start()

        XCTAssertTrue(terminal.viewport()[0].contains("SECOND"))

        terminal.clearOperationLog()
        XCTAssertTrue(tui.hideOverlay())
        XCTAssertTrue(terminal.viewport()[0].contains("FIRST"))
        XCTAssertFalse(terminal.viewport()[0].contains("SECOND"))
    }

    func testOverlaysAtDifferentPositionsDoNotInterfere() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 8)
        let tui = PiTUI(terminal: terminal)
        tui.addChild(EmptyComponent())

        tui.showOverlay(StaticOverlayComponent(lines: ["TOP"]), options: .init(width: .absolute(10), anchor: .topLeft))
        tui.showOverlay(StaticOverlayComponent(lines: ["BOTTOM"]), options: .init(width: .absolute(10), anchor: .bottomRight))
        tui.start()

        XCTAssertTrue(terminal.viewport()[0].contains("TOP"))
        XCTAssertTrue(terminal.viewport()[7].contains("BOTTOM"))
    }

    func testOverlayMaxHeightTruncatesRenderedLines() {
        let terminal = PiTUIVirtualTerminal(columns: 40, rows: 10)
        let tui = PiTUI(terminal: terminal)
        tui.addChild(EmptyComponent())
        let overlay = StaticOverlayComponent(lines: ["L1", "L2", "L3", "L4"])

        tui.showOverlay(overlay, options: .init(width: .absolute(10), maxHeight: .absolute(2), anchor: .topLeft))
        tui.start()

        let viewportText = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewportText.contains("L1"))
        XCTAssertTrue(viewportText.contains("L2"))
        XCTAssertFalse(viewportText.contains("L3"))
        XCTAssertFalse(viewportText.contains("L4"))
    }

    func testOverlayCompositingOnStyledBaseAndWideCharsDoesNotCrashAndShowsOverlay() {
        let terminal = PiTUIVirtualTerminal(columns: 30, rows: 8)
        let tui = PiTUI(terminal: terminal)
        tui.addChild(StyledContent())
        let overlay = StaticOverlayComponent(lines: ["中文OVERLAY"])

        tui.showOverlay(overlay, options: .init(width: .absolute(15), anchor: .center))
        tui.start()

        let viewportText = terminal.viewport().joined(separator: "\n")
        XCTAssertTrue(viewportText.contains("OVERLAY"))
    }
}
