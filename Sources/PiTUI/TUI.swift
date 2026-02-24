public final class PiTUI: PiTUIContainer {
    public let terminal: PiTUITerminal
    public let scheduler: PiTUIRenderScheduler

    private var renderBuffer = PiTUIRenderBuffer()
    private var started = false
    private var clearOnShrink = false
    private var fullRedrawCount = 0
    private var renderRequested = false
    private var showHardwareCursor = false
    private var renderGeneration: UInt64 = 0

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
        renderGeneration &+= 1
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
        renderRequested = false
        renderBuffer.reset()
        renderGeneration &+= 1
    }

    public func requestRender(force: Bool = false) {
        guard started else { return }
        if force {
            renderBuffer.reset()
        }
        if renderRequested { return }
        renderRequested = true
        let generation = renderGeneration
        scheduler.schedule { [weak self] in
            guard let self else { return }
            guard self.renderGeneration == generation else { return }
            self.renderRequested = false
            guard self.started else { return }
            self.doRender()
        }
    }

    private func doRender() {
        guard started else { return }
        var renderedLines = render(width: terminal.columns)
        let cursorPosition = extractCursorPosition(from: &renderedLines)
        renderedLines = sanitizeRenderedLines(renderedLines, width: terminal.columns)
        let viewport = projectToViewport(lines: renderedLines, cursorPosition: cursorPosition, rows: terminal.rows)

        let step = renderBuffer.makeStep(
            width: terminal.columns,
            newLines: viewport.lines,
            clearOnShrink: clearOnShrink
        )

        if step.isFullRedraw {
            fullRedrawCount += 1
        }

        switch step.plan {
        case .none:
            break
        case .fullRedraw(let clearScreen, let lines):
            terminal.beginSynchronizedOutput()
            if clearScreen {
                terminal.clearScreen()
            }
            applyFull(lines: lines)
            terminal.endSynchronizedOutput()
        case .differential(let edits, let clearedRows):
            terminal.beginSynchronizedOutput()
            for edit in edits {
                terminal.writeLine(row: edit.row, content: edit.content)
            }
            for row in clearedRows {
                terminal.clearLine(row: row)
            }
            terminal.endSynchronizedOutput()
        }

        applyHardwareCursor(viewport.cursorPosition)
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

    private func sanitizeRenderedLines(_ lines: [String], width: Int) -> [String] {
        lines.map { PiTUIANSIText.sanitizeLine($0, columns: width) }
    }

    private func projectToViewport(
        lines: [String],
        cursorPosition: PiTUITerminalCursorPosition?,
        rows: Int
    ) -> PiTUIViewportProjection {
        let visibleRows = max(1, rows)
        let viewportStart = max(0, lines.count - visibleRows)
        let viewportLines = Array(lines.suffix(visibleRows))

        let projectedCursor: PiTUITerminalCursorPosition?
        if let cursorPosition {
            if cursorPosition.row < viewportStart || cursorPosition.row >= viewportStart + visibleRows {
                projectedCursor = nil
            } else {
                projectedCursor = .init(row: cursorPosition.row - viewportStart, column: cursorPosition.column)
            }
        } else {
            projectedCursor = nil
        }

        return .init(lines: viewportLines, cursorPosition: projectedCursor)
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

private struct PiTUIViewportProjection {
    var lines: [String]
    var cursorPosition: PiTUITerminalCursorPosition?
}
