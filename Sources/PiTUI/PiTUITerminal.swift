public protocol PiTUITerminal: AnyObject {
    var columns: Int { get }
    var rows: Int { get }

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void)
    func stop()

    func beginSynchronizedOutput()
    func endSynchronizedOutput()
    func hideCursor()
    func showCursor()
    func setCursorPosition(row: Int, column: Int)
    func clearScreen()
    func writeLine(row: Int, content: String)
    func clearLine(row: Int)
}

public final class PiTUIVirtualTerminal: PiTUITerminal {
    public enum Operation: Equatable {
        case start
        case stop
        case hideCursor
        case showCursor
        case setCursorPosition(row: Int, column: Int)
        case clearScreen
        case writeLine(row: Int, content: String)
        case clearLine(row: Int)
        case resize(columns: Int, rows: Int)
    }

    public private(set) var columns: Int
    public private(set) var rows: Int
    public private(set) var operationLog: [Operation] = []

    private var onInput: ((String) -> Void)?
    private var onResize: (() -> Void)?
    private var visibleLines: [String]
    public private(set) var cursorPosition: CursorPosition?

    public struct CursorPosition: Equatable {
        public var row: Int
        public var column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.visibleLines = Array(repeating: "", count: max(1, rows))
    }

    public func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        self.onInput = onInput
        self.onResize = onResize
        operationLog.append(.start)
    }

    public func stop() {
        onInput = nil
        onResize = nil
        operationLog.append(.stop)
    }

    public func beginSynchronizedOutput() {}

    public func endSynchronizedOutput() {}

    public func hideCursor() {
        cursorPosition = nil
        operationLog.append(.hideCursor)
    }

    public func showCursor() {
        operationLog.append(.showCursor)
    }

    public func setCursorPosition(row: Int, column: Int) {
        guard row >= 0, row < rows else { return }
        cursorPosition = .init(row: row, column: max(0, column))
        operationLog.append(.setCursorPosition(row: row, column: max(0, column)))
    }

    public func clearScreen() {
        visibleLines = Array(repeating: "", count: rows)
        cursorPosition = nil
        operationLog.append(.clearScreen)
    }

    public func writeLine(row: Int, content: String) {
        guard row >= 0, row < rows else { return }
        let sanitized = PiTUIANSIText.sanitizeLine(content, columns: columns)
        visibleLines[row] = sanitized
        operationLog.append(.writeLine(row: row, content: sanitized))
    }

    public func clearLine(row: Int) {
        guard row >= 0, row < rows else { return }
        visibleLines[row] = ""
        operationLog.append(.clearLine(row: row))
    }

    public func viewport() -> [String] {
        visibleLines
    }

    public func clearOperationLog() {
        operationLog.removeAll()
    }

    public func resize(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        if visibleLines.count < self.rows {
            visibleLines.append(contentsOf: Array(repeating: "", count: self.rows - visibleLines.count))
        } else if visibleLines.count > self.rows {
            visibleLines = Array(visibleLines.prefix(self.rows))
        }
        operationLog.append(.resize(columns: self.columns, rows: self.rows))
        onResize?()
    }

    public func sendInput(_ value: String) {
        onInput?(value)
    }
}
