import XCTest
@testable import PiTUI

final class PiTUISynchronizedOutputTests: XCTestCase {
    final class TestComponent: PiTUIComponent {
        var lines: [String] = []
        func render(width: Int) -> [String] { lines }
        func invalidate() {}
    }

    final class SpyTerminal: PiTUITerminal {
        enum Event: Equatable {
            case start
            case stop
            case beginSync
            case endSync
            case hideCursor
            case showCursor
            case setCursorPosition(row: Int, column: Int)
            case clearScreen
            case writeLine(row: Int, content: String)
            case clearLine(row: Int)
        }

        var columns: Int = 40
        var rows: Int = 10
        var events: [Event] = []
        private var onResize: (() -> Void)?
        private var onInput: ((String) -> Void)?

        func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
            self.onInput = onInput
            self.onResize = onResize
            events.append(.start)
        }

        func stop() {
            events.append(.stop)
            onInput = nil
            onResize = nil
        }

        func beginSynchronizedOutput() {
            events.append(.beginSync)
        }

        func endSynchronizedOutput() {
            events.append(.endSync)
        }

        func hideCursor() {
            events.append(.hideCursor)
        }

        func showCursor() {
            events.append(.showCursor)
        }

        func setCursorPosition(row: Int, column: Int) {
            events.append(.setCursorPosition(row: row, column: column))
        }

        func clearScreen() {
            events.append(.clearScreen)
        }

        func writeLine(row: Int, content: String) {
            events.append(.writeLine(row: row, content: content))
        }

        func clearLine(row: Int) {
            events.append(.clearLine(row: row))
        }
    }

    func testFirstRenderIsWrappedInSynchronizedOutput() {
        let terminal = SpyTerminal()
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        component.lines = ["Line 0"]
        tui.addChild(component)

        tui.start()

        guard let beginIndex = terminal.events.firstIndex(of: .beginSync),
              let endIndex = terminal.events.firstIndex(of: .endSync) else {
            return XCTFail("Expected synchronized output begin/end")
        }

        XCTAssertLessThan(beginIndex, endIndex)
        XCTAssertTrue(terminal.events[beginIndex...endIndex].contains(.writeLine(row: 0, content: "Line 0")))
    }

    func testDifferentialRenderIsWrappedInSynchronizedOutput() {
        let terminal = SpyTerminal()
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        component.lines = ["Line 0", "Line 1"]
        tui.addChild(component)
        tui.start()

        terminal.events.removeAll()
        component.lines = ["Line 0", "Changed"]
        tui.requestRender()

        XCTAssertEqual(terminal.events.first, .beginSync)
        XCTAssertEqual(terminal.events.last, .endSync)
        XCTAssertTrue(terminal.events.contains(.writeLine(row: 1, content: "Changed")))
    }

    func testNoopRenderDoesNotEmitSynchronizedOutput() {
        let terminal = SpyTerminal()
        let tui = PiTUI(terminal: terminal)
        let component = TestComponent()
        component.lines = ["Line 0"]
        tui.addChild(component)
        tui.start()

        terminal.events.removeAll()
        tui.requestRender()

        XCTAssertFalse(terminal.events.contains(.beginSync))
        XCTAssertFalse(terminal.events.contains(.endSync))
    }
}
