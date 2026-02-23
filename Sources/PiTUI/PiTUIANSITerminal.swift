import Foundation

public final class PiTUIANSITerminal: PiTUITerminal {
    public private(set) var columns: Int
    public private(set) var rows: Int

    private let writeOutput: @Sendable (String) -> Void
    private var onInput: ((String) -> Void)?
    private var onResize: (() -> Void)?

    public init(
        columns: Int,
        rows: Int,
        writer: @escaping @Sendable (String) -> Void
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.writeOutput = writer
    }

    public func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        self.onInput = onInput
        self.onResize = onResize
    }

    public func stop() {
        onInput = nil
        onResize = nil
    }

    public func beginSynchronizedOutput() {
        writeOutput("\u{001B}[?2026h")
    }

    public func endSynchronizedOutput() {
        writeOutput("\u{001B}[?2026l")
    }

    public func hideCursor() {
        writeOutput("\u{001B}[?25l")
    }

    public func showCursor() {
        writeOutput("\u{001B}[?25h")
    }

    public func setCursorPosition(row: Int, column: Int) {
        guard isValidRow(row) else { return }
        writeOutput("\u{001B}[\(row + 1);\(max(0, column) + 1)H")
    }

    public func clearScreen() {
        writeOutput("\u{001B}[2J\u{001B}[H")
    }

    public func writeLine(row: Int, content: String) {
        guard isValidRow(row) else { return }
        let sanitized = PiTUIANSIText.sanitizeLine(content, columns: columns)
        writeOutput(cursorMove(row: row) + "\u{001B}[2K" + sanitized)
    }

    public func clearLine(row: Int) {
        guard isValidRow(row) else { return }
        writeOutput(cursorMove(row: row) + "\u{001B}[2K")
    }

    public func resize(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        onResize?()
    }

    public func simulateInput(_ data: String) {
        onInput?(data)
    }

    private func isValidRow(_ row: Int) -> Bool {
        row >= 0 && row < rows
    }

    private func cursorMove(row: Int) -> String {
        "\u{001B}[\(row + 1);1H"
    }
}
