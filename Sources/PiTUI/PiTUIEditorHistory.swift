public final class PiTUIEditorHistory {
    private var history: [String] = []
    private var browsingIndex: Int = -1 // -1 = not browsing
    private var currentDraft: String = ""

    public init() {}

    public var count: Int { history.count }
    public var isBrowsing: Bool { browsingIndex >= 0 }
    public var historyIndex: Int { browsingIndex }

    public func entries() -> [String] {
        history
    }

    public func addToHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if history.first == trimmed { return }
        history.insert(trimmed, at: 0)
        if history.count > 100 {
            history.removeLast(history.count - 100)
        }
    }

    public func resetBrowsing() {
        browsingIndex = -1
        currentDraft = ""
    }

    public func updateCurrentDraft(_ text: String) {
        if browsingIndex >= 0 {
            browsingIndex = -1
        }
        currentDraft = text
    }

    public func navigateUp(currentText: String) -> String? {
        navigate(direction: -1, currentText: currentText)
    }

    public func navigateDown(currentText: String) -> String? {
        navigate(direction: 1, currentText: currentText)
    }

    private func navigate(direction: Int, currentText: String) -> String? {
        guard !history.isEmpty else { return nil }
        let newIndex = browsingIndex - direction
        guard newIndex >= -1, newIndex < history.count else { return nil }

        if browsingIndex == -1, newIndex >= 0 {
            currentDraft = currentText
        }

        browsingIndex = newIndex
        if browsingIndex == -1 {
            return currentDraft
        }
        return history[browsingIndex]
    }
}
