public final class PiTUIEditorComponent: PiTUIComponent {
    public let model: PiTUIEditorModel
    public var prompt: String

    public var onSubmit: ((String) -> Void)?
    public var onChange: ((String) -> Void)?
    public var onEscape: (() -> Void)?

    private let history = PiTUIEditorHistory()
    private var suppressHistoryDraftUpdate = false

    public init(
        model: PiTUIEditorModel = PiTUIEditorModel(),
        prompt: String = "> "
    ) {
        self.model = model
        self.prompt = prompt
    }

    public func getText() -> String {
        model.getText()
    }

    public func setText(_ text: String) {
        let before = model.getText()
        model.setText(text)
        emitChangeIfNeeded(previous: before)
    }

    public func addToHistory(_ text: String) {
        history.addToHistory(text)
    }

    public func handleInput(_ data: String) {
        let kb = PiTUIEditorKeybindings.get()
        let before = model.getText()

        if PiTUIKeys.matchesKey(data, "shift+enter") {
            model.insertNewline()
            emitChangeIfNeeded(previous: before)
            return
        }
        if kb.matches(data, action: .submit) || data == "\r" {
            onSubmit?(model.getText())
            return
        }
        if kb.matches(data, action: .selectCancel) {
            onEscape?()
            return
        }

        if kb.matches(data, action: .cursorUp) {
            if (history.isBrowsing || model.cursorPosition.line == 0),
               let next = history.navigateUp(currentText: model.getText()) {
                suppressHistoryDraftUpdate = true
                model.setText(next)
                emitChangeIfNeeded(previous: before)
                suppressHistoryDraftUpdate = false
                return
            }
            model.moveCursorUp()
            return
        }
        if kb.matches(data, action: .cursorDown) {
            if history.isBrowsing,
               let next = history.navigateDown(currentText: model.getText()) {
                suppressHistoryDraftUpdate = true
                model.setText(next)
                emitChangeIfNeeded(previous: before)
                suppressHistoryDraftUpdate = false
                return
            }
            model.moveCursorDown()
            return
        }
        if kb.matches(data, action: .cursorLeft) {
            model.moveCursorLeft()
            return
        }
        if kb.matches(data, action: .cursorRight) {
            model.moveCursorRight()
            return
        }
        if kb.matches(data, action: .cursorLineStart) {
            model.setCursor(line: model.cursorPosition.line, colUTF16: 0)
            return
        }
        if kb.matches(data, action: .cursorLineEnd) {
            let line = model.lines[model.cursorPosition.line]
            model.setCursor(line: model.cursorPosition.line, colUTF16: line.utf16.count)
            return
        }
        if kb.matches(data, action: .deleteCharBackward) {
            model.backspace()
            emitChangeIfNeeded(previous: before)
            return
        }
        if kb.matches(data, action: .deleteCharForward) {
            model.deleteForward()
            emitChangeIfNeeded(previous: before)
            return
        }
        if kb.matches(data, action: .undo) {
            model.undo()
            emitChangeIfNeeded(previous: before)
            return
        }

        if containsControlCharacters(data) {
            return
        }
        model.insertTextAtCursor(data)
        emitChangeIfNeeded(previous: before)
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        let cursor = model.cursorPosition
        return model.lines.enumerated().map { index, line in
            let prefix = index == 0 ? prompt : ""
            if index == cursor.line {
                let splitIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
                let before = String(line[..<splitIndex])
                let after = String(line[splitIndex...])
                return prefix + before + PiTUICursor.marker + after
            }
            return prefix + line
        }
    }

    private func emitChangeIfNeeded(previous: String) {
        let current = model.getText()
        if current != previous {
            if !suppressHistoryDraftUpdate {
                history.updateCurrentDraft(current)
            }
            onChange?(current)
        }
    }

    private func containsControlCharacters(_ data: String) -> Bool {
        data.unicodeScalars.contains { scalar in
            let v = scalar.value
            return v < 32 || v == 0x7F || (v >= 0x80 && v <= 0x9F)
        }
    }

    private func stringIndex(in string: String, utf16Offset: Int) -> String.Index {
        let clamped = max(0, min(utf16Offset, string.utf16.count))
        let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: string) ?? string.endIndex
    }
}
