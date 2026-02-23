import XCTest
@testable import PiTUI

final class PiTUIProcessTerminalTests: XCTestCase {
    final class MockHost: PiTUITerminalHost {
        var columns: Int
        var rows: Int
        var writes: [String] = []
        var started = false
        var stopped = false

        private var onInput: ((String) -> Void)?
        private var onResize: ((Int, Int) -> Void)?

        init(columns: Int = 80, rows: Int = 24) {
            self.columns = columns
            self.rows = rows
        }

        func start(
            onInput: @escaping (String) -> Void,
            onResize: @escaping (Int, Int) -> Void
        ) {
            started = true
            self.onInput = onInput
            self.onResize = onResize
        }

        func stop() {
            stopped = true
            onInput = nil
            onResize = nil
        }

        func write(_ output: String) {
            writes.append(output)
        }

        func simulateInput(_ data: String) {
            onInput?(data)
        }

        func simulateResize(columns: Int, rows: Int) {
            self.columns = columns
            self.rows = rows
            onResize?(columns, rows)
        }
    }

    func testDelegatesANSIOutputThroughHostWriter() {
        let host = MockHost(columns: 10, rows: 5)
        let terminal = PiTUIProcessTerminal(host: host)

        terminal.beginSynchronizedOutput()
        terminal.writeLine(row: 1, content: "hello")
        terminal.endSynchronizedOutput()

        XCTAssertEqual(
            host.writes,
            [
                "\u{001B}[?2026h",
                "\u{001B}[2;1H\u{001B}[2Khello",
                "\u{001B}[?2026l"
            ]
        )
    }

    func testStartBridgesInputAndResizeCallbacksAndUpdatesDimensions() {
        let host = MockHost(columns: 40, rows: 10)
        let terminal = PiTUIProcessTerminal(host: host)
        var inputs: [String] = []
        var resizeCount = 0

        terminal.start(
            onInput: { inputs.append($0) },
            onResize: { resizeCount += 1 }
        )

        XCTAssertTrue(host.started)
        host.simulateInput("abc")
        host.simulateResize(columns: 100, rows: 30)

        XCTAssertEqual(inputs, ["abc"])
        XCTAssertEqual(resizeCount, 1)
        XCTAssertEqual(terminal.columns, 100)
        XCTAssertEqual(terminal.rows, 30)
    }

    func testStopDelegatesToHost() {
        let host = MockHost()
        let terminal = PiTUIProcessTerminal(host: host)

        terminal.stop()

        XCTAssertTrue(host.stopped)
    }

    func testStandardIOHostWritesViaInjectedWriterAndClampsDimensions() {
        var writes: [String] = []
        let host = PiTUIStandardIOHost(columns: 0, rows: -1) { output in
            writes.append(output)
        }

        XCTAssertEqual(host.columns, 1)
        XCTAssertEqual(host.rows, 1)

        host.write("x")
        XCTAssertEqual(writes, ["x"])

        host.updateSize(columns: 0, rows: 2)
        XCTAssertEqual(host.columns, 1)
        XCTAssertEqual(host.rows, 2)
    }
}
