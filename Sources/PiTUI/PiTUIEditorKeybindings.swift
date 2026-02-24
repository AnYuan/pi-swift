import Foundation

public typealias PiTUIKeyID = String

public enum PiTUIEditorAction: String, CaseIterable, Sendable {
    case cursorUp
    case cursorDown
    case cursorLeft
    case cursorRight
    case cursorWordLeft
    case cursorWordRight
    case cursorLineStart
    case cursorLineEnd
    case deleteCharBackward
    case deleteCharForward
    case deleteWordBackward
    case deleteWordForward
    case deleteToLineStart
    case deleteToLineEnd
    case submit
    case selectUp
    case selectDown
    case selectConfirm
    case selectCancel
    case yank
    case yankPop
    case undo
}

public typealias PiTUIEditorKeybindingsConfig = [PiTUIEditorAction: [PiTUIKeyID]]

public final class PiTUIEditorKeybindingsManager {
    public static let defaultBindings: [PiTUIEditorAction: [PiTUIKeyID]] = [
        .cursorUp: ["up"],
        .cursorDown: ["down"],
        .cursorLeft: ["left", "ctrl+b"],
        .cursorRight: ["right", "ctrl+f"],
        .cursorWordLeft: ["alt+left", "alt+b"],
        .cursorWordRight: ["alt+right", "alt+f"],
        .cursorLineStart: ["home", "ctrl+a"],
        .cursorLineEnd: ["end", "ctrl+e"],
        .deleteCharBackward: ["backspace"],
        .deleteCharForward: ["delete", "ctrl+d"],
        .deleteWordBackward: ["ctrl+w", "alt+backspace"],
        .deleteWordForward: ["alt+d"],
        .deleteToLineStart: ["ctrl+u"],
        .deleteToLineEnd: ["ctrl+k"],
        .submit: ["enter"],
        .selectUp: ["up"],
        .selectDown: ["down"],
        .selectConfirm: ["enter"],
        // newline is handled as shift+enter in components/models that support multi-line editing
        .selectCancel: ["escape", "ctrl+c"],
        .yank: ["ctrl+y"],
        .yankPop: ["alt+y"],
        .undo: ["ctrl+z", "ctrl+-"]
    ]

    private var actionToKeys: [PiTUIEditorAction: [PiTUIKeyID]]

    public init(config: PiTUIEditorKeybindingsConfig = [:]) {
        actionToKeys = Self.defaultBindings
        setConfig(config)
    }

    public func matches(_ data: String, action: PiTUIEditorAction) -> Bool {
        guard let keys = actionToKeys[action] else { return false }
        return keys.contains { PiTUIKeys.matchesKey(data, $0) }
    }

    public func keys(for action: PiTUIEditorAction) -> [PiTUIKeyID] {
        actionToKeys[action] ?? []
    }

    public func setConfig(_ config: PiTUIEditorKeybindingsConfig) {
        for (action, keys) in config {
            actionToKeys[action] = keys
        }
    }
}

public enum PiTUIEditorKeybindings {
    private final class GlobalState: @unchecked Sendable {
        private let lock = NSLock()
        private var manager = PiTUIEditorKeybindingsManager()

        func get() -> PiTUIEditorKeybindingsManager {
            lock.lock()
            let value = manager
            lock.unlock()
            return value
        }

        func set(_ manager: PiTUIEditorKeybindingsManager) {
            lock.lock()
            self.manager = manager
            lock.unlock()
        }
    }

    private static let globalState = GlobalState()

    public static func get() -> PiTUIEditorKeybindingsManager {
        globalState.get()
    }

    public static func set(_ manager: PiTUIEditorKeybindingsManager) {
        globalState.set(manager)
    }
}
