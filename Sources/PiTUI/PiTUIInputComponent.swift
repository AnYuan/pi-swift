public final class PiTUIInputComponent: PiTUIComponent {
    public let model: PiTUIInputModel
    public var prompt: String
    public var focused: Bool = false

    public var onSubmit: ((String) -> Void)?
    public var onEscape: (() -> Void)?

    public init(
        model: PiTUIInputModel = PiTUIInputModel(),
        prompt: String = "> "
    ) {
        self.model = model
        self.prompt = prompt
    }

    public func getValue() -> String {
        model.value
    }

    public func setValue(_ value: String) {
        model.setValue(value)
    }

    public func handleInput(_ data: String) {
        if PiTUIKeys.matchesKey(data, "enter") || data == "\n" || data == "\r" {
            onSubmit?(model.value)
            return
        }
        if PiTUIKeys.matchesKey(data, "escape") || PiTUIKeys.matchesKey(data, "esc") {
            onEscape?()
            return
        }
        model.handleInput(data)
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        let cursorIndex = stringIndex(forUTF16Offset: model.cursorUTF16, in: model.value)
        let before = String(model.value[..<cursorIndex])
        let after = String(model.value[cursorIndex...])
        let line = prompt + before + PiTUICursor.marker + after

        if width <= 0 { return [""] }
        return [line]
    }

    private func stringIndex(forUTF16Offset offset: Int, in string: String) -> String.Index {
        let clamped = max(0, min(offset, string.utf16.count))
        let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: string) ?? string.endIndex
    }
}
