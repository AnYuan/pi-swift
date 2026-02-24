import Foundation
import PiTUI

public final class PiCodingAgentInteractiveSession {
    public let mode: PiCodingAgentInteractiveMode
    public let tui: PiTUI

    public init(
        mode: PiCodingAgentInteractiveMode,
        terminal: PiTUITerminal,
        scheduler: PiTUIRenderScheduler = PiTUIImmediateRenderScheduler()
    ) {
        self.mode = mode
        self.tui = PiTUI(terminal: terminal, scheduler: scheduler)
        self.tui.addChild(mode)
    }

    public func start() {
        tui.start()
    }

    public func stop() {
        tui.stop()
    }

    public func handleInput(_ data: String) {
        mode.handleInput(data)
        tui.requestRender()
    }

    public func handleKeyID(_ keyID: String) {
        mode.handleKeyID(keyID)
        tui.requestRender()
    }
}
