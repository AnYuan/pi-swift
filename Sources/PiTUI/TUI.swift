public final class PiTUI: PiTUIContainer {
    public let terminal: PiTUITerminal
    public let scheduler: PiTUIRenderScheduler

    private var renderBuffer = PiTUIRenderBuffer()
    private var started = false
    private var clearOnShrink = false
    private var fullRedrawCount = 0
    private var renderRequested = false
    private var showHardwareCursor = false

    public init(
        terminal: PiTUITerminal,
        scheduler: PiTUIRenderScheduler = PiTUIImmediateRenderScheduler()
    ) {
        self.terminal = terminal
        self.scheduler = scheduler
        super.init()
    }

    public var fullRedraws: Int {
        fullRedrawCount
    }

    public func getClearOnShrink() -> Bool {
        clearOnShrink
    }

    public func setClearOnShrink(_ enabled: Bool) {
        clearOnShrink = enabled
    }

    public func getShowHardwareCursor() -> Bool {
        showHardwareCursor
    }

    public func setShowHardwareCursor(_ enabled: Bool) {
        showHardwareCursor = enabled
        if !enabled, started {
            terminal.hideCursor()
        }
    }

    public func start() {
        guard !started else { return }
        started = true
        terminal.start(onInput: { _ in }, onResize: { [weak self] in
            self?.requestRender()
        })
        terminal.hideCursor()
        requestRender()
    }

    public func stop() {
        guard started else { return }
        terminal.showCursor()
        terminal.stop()
        started = false
    }

    public func requestRender(force: Bool = false) {
        guard started else { return }
        if force {
            renderBuffer.reset()
        }
        if renderRequested { return }
        renderRequested = true
        scheduler.schedule { [weak self] in
            guard let self else { return }
            self.renderRequested = false
            self.doRender()
        }
    }

    private func doRender() {
        var renderedLines = render(width: terminal.columns)
        let cursorPosition = extractCursorPosition(from: &renderedLines)

        let step = renderBuffer.makeStep(
            width: terminal.columns,
            newLines: renderedLines,
            clearOnShrink: clearOnShrink
        )

        if step.isFullRedraw {
            fullRedrawCount += 1
        }

        switch step.plan {
        case .none:
            break
        case .fullRedraw(let clearScreen, let lines):
            if clearScreen {
                terminal.clearScreen()
            }
            applyFull(lines: lines)
        case .differential(let edits, let clearedRows):
            for edit in edits {
                terminal.writeLine(row: edit.row, content: edit.content)
            }
            for row in clearedRows {
                terminal.clearLine(row: row)
            }
        }

        applyHardwareCursor(cursorPosition)
    }

    private func applyFull(lines: [String]) {
        for row in 0..<terminal.rows {
            if row < lines.count {
                terminal.writeLine(row: row, content: lines[row])
            } else {
                terminal.clearLine(row: row)
            }
        }
    }

    private func extractCursorPosition(from lines: inout [String]) -> PiTUITerminalCursorPosition? {
        for row in stride(from: lines.count - 1, through: 0, by: -1) where row >= 0 {
            let line = lines[row]
            guard let range = line.range(of: PiTUICursor.marker) else { continue }
            let beforeMarker = String(line[..<range.lowerBound])
            let afterMarker = String(line[range.upperBound...])
            let column = PiTUIANSIText.visibleWidth(beforeMarker)
            lines[row] = beforeMarker + afterMarker
            return .init(row: row, column: column)
        }
        return nil
    }

    private func applyHardwareCursor(_ cursorPosition: PiTUITerminalCursorPosition?) {
        guard showHardwareCursor else {
            return
        }
        guard let cursorPosition else {
            terminal.hideCursor()
            return
        }
        terminal.setCursorPosition(row: cursorPosition.row, column: cursorPosition.column)
        terminal.showCursor()
    }
}

private struct PiTUITerminalCursorPosition {
    var row: Int
    var column: Int
}
