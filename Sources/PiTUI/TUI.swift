public final class PiTUI: PiTUIContainer {
    public let terminal: PiTUITerminal
    public let scheduler: PiTUIRenderScheduler

    private var renderBuffer = PiTUIRenderBuffer()
    private var started = false
    private var clearOnShrink = false
    private var fullRedrawCount = 0
    private var renderRequested = false

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
        let step = renderBuffer.makeStep(
            width: terminal.columns,
            newLines: render(width: terminal.columns),
            clearOnShrink: clearOnShrink
        )

        if step.isFullRedraw {
            fullRedrawCount += 1
        }

        switch step.plan {
        case .none:
            return
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
}
