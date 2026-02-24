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
    private var overlays: [PiTUIOverlayEntry] = []

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

    public func showOverlay(_ component: PiTUIComponent, options: PiTUIOverlayOptions = .init()) {
        overlays.append(.init(component: component, options: options))
        if started {
            requestRender()
        }
    }

    @discardableResult
    public func hideOverlay() -> Bool {
        guard !overlays.isEmpty else { return false }
        overlays.removeLast()
        if started {
            requestRender()
        }
        return true
    }

    private func doRender() {
        guard started else { return }
        var renderedLines = render(width: terminal.columns)
        let cursorPosition = extractCursorPosition(from: &renderedLines)
        renderedLines = sanitizeRenderedLines(renderedLines, width: terminal.columns)
        let viewport = projectToViewport(lines: renderedLines, cursorPosition: cursorPosition, rows: terminal.rows)
        let compositedViewportLines = compositeOverlays(on: viewport.lines)

        let step = renderBuffer.makeStep(
            width: terminal.columns,
            newLines: compositedViewportLines,
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

    private func compositeOverlays(on viewportLines: [String]) -> [String] {
        guard !overlays.isEmpty else { return viewportLines }

        let rows = max(1, terminal.rows)
        let cols = max(1, terminal.columns)
        var canvas = Array(repeating: Array(repeating: "", count: cols), count: rows)

        for row in 0..<min(rows, viewportLines.count) {
            canvas[row] = visibleCells(from: viewportLines[row], columns: cols)
        }

        for entry in overlays {
            let provisional = PiTUIOverlayLayoutPlanner.resolve(
                options: entry.options,
                overlayHeight: 0,
                termWidth: cols,
                termHeight: rows
            )
            var overlayLines = entry.component.render(width: provisional.width)

            let layout = PiTUIOverlayLayoutPlanner.resolve(
                options: entry.options,
                overlayHeight: overlayLines.count,
                termWidth: cols,
                termHeight: rows
            )

            if let maxHeight = layout.maxHeight, overlayLines.count > maxHeight {
                overlayLines = Array(overlayLines.prefix(maxHeight))
            }

            for (index, line) in overlayLines.enumerated() {
                let targetRow = layout.row + index
                guard targetRow >= 0, targetRow < rows else { continue }
                let overlayCells = visibleCells(from: line, columns: layout.width)
                for (offset, cell) in overlayCells.enumerated() where !cell.isEmpty {
                    let targetCol = layout.col + offset
                    guard targetCol >= 0, targetCol < cols else { continue }
                    canvas[targetRow][targetCol] = cell
                }
            }
        }

        return canvas.map { trimTrailingSpaces(from: $0) }
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

private struct PiTUIOverlayEntry {
    var component: PiTUIComponent
    var options: PiTUIOverlayOptions
}

private func visibleCells(from line: String, columns: Int) -> [String] {
    let stripped = stripANSIEscapeSequences(line)
    var cells = Array(repeating: "", count: max(0, columns))
    var col = 0

    for ch in stripped {
        guard col < cells.count else { break }
        if ch == "\n" || ch == "\r" { continue }
        let text = String(ch)
        let width = max(0, PiTUIANSIText.visibleWidth(text))
        if width == 0 { continue }
        if width == 1 {
            cells[col] = text
            col += 1
            continue
        }

        // Wide glyphs occupy two columns; keep a placeholder in the trailing cell.
        if col + 1 >= cells.count { break }
        cells[col] = text
        cells[col + 1] = ""
        col += 2
    }

    return cells
}

private func trimTrailingSpaces(from cells: [String]) -> String {
    var end = cells.count
    while end > 0 {
        let value = cells[end - 1]
        if value.isEmpty || value == " " {
            end -= 1
            continue
        }
        break
    }
    return cells.prefix(end).joined()
}

private func stripANSIEscapeSequences(_ value: String) -> String {
    var output = String.UnicodeScalarView()
    var scalars = Array(value.unicodeScalars)
    var index = 0

    func next() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        defer { index += 1 }
        return scalars[index]
    }

    func peek() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    while let scalar = next() {
        if scalar != "\u{001B}" {
            output.append(scalar)
            continue
        }

        guard let kind = peek() else { break }
        if kind == "[" {
            _ = next()
            while let part = next() {
                if (0x40...0x7E).contains(part.value) { break }
            }
            continue
        }
        if kind == "]" {
            _ = next()
            while let part = next() {
                if part == "\u{0007}" { break }
                if part == "\u{001B}", peek() == "\\" {
                    _ = next()
                    break
                }
            }
            continue
        }

        _ = next()
    }

    return String(output)
}
