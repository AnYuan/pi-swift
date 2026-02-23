import Foundation
import XCTest
@testable import PiTUI

final class PiTUIANSITerminalTests: XCTestCase {
    final class WriteCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            let copy = values
            lock.unlock()
            return copy
        }
    }

    func testCursorVisibilityAndClearScreenEmitExpectedSequences() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 80, rows: 24) { output in
            collector.append(output)
        }

        terminal.hideCursor()
        terminal.showCursor()
        terminal.clearScreen()

        XCTAssertEqual(
            collector.snapshot(),
            [
                "\u{001B}[?25l",
                "\u{001B}[?25h",
                "\u{001B}[2J\u{001B}[H"
            ]
        )
    }

    func testSynchronizedOutputMarkersEmitExpectedSequences() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 80, rows: 24) { output in
            collector.append(output)
        }

        terminal.beginSynchronizedOutput()
        terminal.endSynchronizedOutput()

        XCTAssertEqual(
            collector.snapshot(),
            [
                "\u{001B}[?2026h",
                "\u{001B}[?2026l"
            ]
        )
    }

    func testWriteLineMovesToRowClearsLineAndTruncatesToColumns() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 5, rows: 10) { output in
            collector.append(output)
        }

        terminal.writeLine(row: 2, content: "abcdefg")

        XCTAssertEqual(collector.snapshot(), ["\u{001B}[3;1H\u{001B}[2Kabcde"])
    }

    func testWriteLineUsesANSIVisibleWidthTruncationAndAppendsReset() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 3, rows: 10) { output in
            collector.append(output)
        }

        terminal.writeLine(row: 0, content: "\u{001B}[31mabcdef\u{001B}[0m")

        XCTAssertEqual(
            collector.snapshot(),
            ["\u{001B}[1;1H\u{001B}[2K\u{001B}[31mabc\u{001B}[0m"]
        )
    }

    func testClearLineMovesAndClearsOnlyTargetRow() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 20, rows: 10) { output in
            collector.append(output)
        }

        terminal.clearLine(row: 4)

        XCTAssertEqual(collector.snapshot(), ["\u{001B}[5;1H\u{001B}[2K"])
    }

    func testStartStoresCallbacksAndTestHooksTriggerInputAndResize() {
        let terminal = PiTUIANSITerminal(columns: 40, rows: 10) { _ in }
        var receivedInput: [String] = []
        var resizeCount = 0

        terminal.start(
            onInput: { receivedInput.append($0) },
            onResize: { resizeCount += 1 }
        )

        terminal.simulateInput("abc")
        terminal.resize(columns: 60, rows: 12)

        XCTAssertEqual(receivedInput, ["abc"])
        XCTAssertEqual(resizeCount, 1)
        XCTAssertEqual(terminal.columns, 60)
        XCTAssertEqual(terminal.rows, 12)
    }

    func testOutOfBoundsRowsAreIgnored() {
        let collector = WriteCollector()
        let terminal = PiTUIANSITerminal(columns: 10, rows: 2) { output in
            collector.append(output)
        }

        terminal.writeLine(row: -1, content: "x")
        terminal.writeLine(row: 2, content: "x")
        terminal.clearLine(row: 3)

        XCTAssertTrue(collector.snapshot().isEmpty)
    }
}
