import Foundation

public protocol PiTUITerminalHost: AnyObject {
    var columns: Int { get }
    var rows: Int { get }

    func start(
        onInput: @escaping (String) -> Void,
        onResize: @escaping (_ columns: Int, _ rows: Int) -> Void
    )
    func stop()
    func write(_ output: String)
}

public final class PiTUIProcessTerminal: PiTUITerminal {
    public private(set) var columns: Int
    public private(set) var rows: Int

    private let host: PiTUITerminalHost
    private let ansiTerminal: PiTUIANSITerminal
    private var started = false
    private var sessionGeneration: UInt64 = 0

    public init(host: PiTUITerminalHost) {
        self.host = host
        self.columns = max(1, host.columns)
        self.rows = max(1, host.rows)
        self.ansiTerminal = PiTUIANSITerminal(columns: max(1, host.columns), rows: max(1, host.rows)) { output in
            host.write(output)
        }
    }

    public func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        guard !started else { return }
        started = true
        sessionGeneration &+= 1
        let generation = sessionGeneration
        host.start(
            onInput: { [weak self] value in
                guard let self else { return }
                guard self.started, self.sessionGeneration == generation else { return }
                onInput(value)
            },
            onResize: { [weak self] columns, rows in
                guard let self else { return }
                guard self.started, self.sessionGeneration == generation else { return }
                let c = max(1, columns)
                let r = max(1, rows)
                self.columns = c
                self.rows = r
                self.ansiTerminal.resize(columns: c, rows: r)
                onResize()
            }
        )
    }

    public func stop() {
        guard started else { return }
        started = false
        sessionGeneration &+= 1
        host.stop()
    }

    public func beginSynchronizedOutput() {
        ansiTerminal.beginSynchronizedOutput()
    }

    public func endSynchronizedOutput() {
        ansiTerminal.endSynchronizedOutput()
    }

    public func hideCursor() {
        ansiTerminal.hideCursor()
    }

    public func showCursor() {
        ansiTerminal.showCursor()
    }

    public func setCursorPosition(row: Int, column: Int) {
        ansiTerminal.setCursorPosition(row: row, column: column)
    }

    public func clearScreen() {
        ansiTerminal.clearScreen()
    }

    public func writeLine(row: Int, content: String) {
        ansiTerminal.writeLine(row: row, content: content)
    }

    public func clearLine(row: Int) {
        ansiTerminal.clearLine(row: row)
    }
}

public final class PiTUIStandardIOHost: PiTUITerminalHost {
    public private(set) var columns: Int
    public private(set) var rows: Int

    private let stdoutWriter: (String) -> Void

    public init(
        columns: Int = Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "") ?? 80,
        rows: Int = Int(ProcessInfo.processInfo.environment["LINES"] ?? "") ?? 24,
        stdoutWriter: @escaping (String) -> Void = { output in
            if let data = output.data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        }
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.stdoutWriter = stdoutWriter
    }

    public func start(
        onInput: @escaping (String) -> Void,
        onResize: @escaping (_ columns: Int, _ rows: Int) -> Void
    ) {
        _ = onInput
        _ = onResize
        // Minimal scaffold: actual stdin/raw-mode/signal integration will be added in later slices.
    }

    public func stop() {}

    public func write(_ output: String) {
        stdoutWriter(output)
    }

    public func updateSize(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}
