public struct PiTUISelectItem: Equatable {
    public var value: String
    public var label: String
    public var description: String?

    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

public struct PiTUISelectListTheme: @unchecked Sendable {
    public var selectedPrefix: (String) -> String
    public var selectedText: (String) -> String
    public var description: (String) -> String
    public var scrollInfo: (String) -> String
    public var noMatch: (String) -> String

    public init(
        selectedPrefix: @escaping (String) -> String,
        selectedText: @escaping (String) -> String,
        description: @escaping (String) -> String,
        scrollInfo: @escaping (String) -> String,
        noMatch: @escaping (String) -> String
    ) {
        self.selectedPrefix = selectedPrefix
        self.selectedText = selectedText
        self.description = description
        self.scrollInfo = scrollInfo
        self.noMatch = noMatch
    }

    public static let plain = PiTUISelectListTheme(
        selectedPrefix: { $0 },
        selectedText: { $0 },
        description: { $0 },
        scrollInfo: { $0 },
        noMatch: { $0 }
    )
}

public final class PiTUISelectList: PiTUIComponent {
    private var items: [PiTUISelectItem]
    private var filteredItems: [PiTUISelectItem]
    private var selectedIndex: Int = 0
    private var maxVisible: Int
    private let theme: PiTUISelectListTheme

    public var onSelect: ((PiTUISelectItem) -> Void)?
    public var onCancel: (() -> Void)?
    public var onSelectionChange: ((PiTUISelectItem) -> Void)?

    public init(
        items: [PiTUISelectItem],
        maxVisible: Int = 5,
        theme: PiTUISelectListTheme = .plain
    ) {
        self.items = items
        self.filteredItems = items
        self.maxVisible = max(1, maxVisible)
        self.theme = theme
    }

    public func setItems(_ items: [PiTUISelectItem]) {
        self.items = items
        self.filteredItems = items
        selectedIndex = 0
    }

    public func setFilter(_ filter: String) {
        let needle = filter.lowercased()
        filteredItems = items.filter { $0.value.lowercased().hasPrefix(needle) }
        selectedIndex = 0
        notifySelectionChange()
    }

    public func setSelectedIndex(_ index: Int) {
        selectedIndex = clampSelectedIndex(index)
        notifySelectionChange()
    }

    public func getSelectedItem() -> PiTUISelectItem? {
        guard filteredItems.indices.contains(selectedIndex) else { return nil }
        return filteredItems[selectedIndex]
    }

    public func handleInput(_ data: String) {
        let kb = PiTUIEditorKeybindings.get()
        guard !filteredItems.isEmpty else {
            if kb.matches(data, action: .selectCancel) { onCancel?() }
            return
        }

        if kb.matches(data, action: .selectUp) {
            selectedIndex = selectedIndex == 0 ? filteredItems.count - 1 : selectedIndex - 1
            notifySelectionChange()
            return
        }
        if kb.matches(data, action: .selectDown) {
            selectedIndex = selectedIndex == filteredItems.count - 1 ? 0 : selectedIndex + 1
            notifySelectionChange()
            return
        }
        if kb.matches(data, action: .selectConfirm) {
            if let selected = getSelectedItem() { onSelect?(selected) }
            return
        }
        if kb.matches(data, action: .selectCancel) {
            onCancel?()
        }
    }

    public func invalidate() {}

    public func render(width: Int) -> [String] {
        let width = max(1, width)
        guard !filteredItems.isEmpty else {
            return [theme.noMatch("  No matching commands")]
        }

        let startIndex = max(0, min(selectedIndex - maxVisible / 2, filteredItems.count - maxVisible))
        let endIndex = min(startIndex + maxVisible, filteredItems.count)

        var lines: [String] = []
        for i in startIndex..<endIndex {
            let item = filteredItems[i]
            let isSelected = i == selectedIndex
            let displayValue = item.label.isEmpty ? item.value : item.label
            let description = item.description.map(Self.normalizeToSingleLine)

            if isSelected {
                let prefix = theme.selectedPrefix("→ ")
                let maxWidth = max(0, width - 2)
                let base = truncate(displayValue, width: maxWidth)
                let line = prefix + base
                if let description, width > 40 {
                    lines.append(theme.selectedText(line + " " + truncate(description, width: max(0, width - visibleWidth(line) - 1))))
                } else {
                    lines.append(theme.selectedText(line))
                }
            } else {
                let prefix = "  "
                let base = prefix + truncate(displayValue, width: max(0, width - prefix.count))
                if let description, width > 40 {
                    let descSpace = max(0, width - visibleWidth(base) - 1)
                    let desc = theme.description(" " + truncate(description, width: descSpace))
                    lines.append(base + desc)
                } else {
                    lines.append(base)
                }
            }
        }

        if startIndex > 0 || endIndex < filteredItems.count {
            let info = "  (\(selectedIndex + 1)/\(filteredItems.count))"
            lines.append(theme.scrollInfo(truncate(info, width: width)))
        }

        return lines
    }

    private func clampSelectedIndex(_ index: Int) -> Int {
        guard !filteredItems.isEmpty else { return 0 }
        return max(0, min(index, filteredItems.count - 1))
    }

    private func notifySelectionChange() {
        guard let item = getSelectedItem() else { return }
        onSelectionChange?(item)
    }

    private static func normalizeToSingleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private func truncate(_ text: String, width: Int) -> String {
        PiTUIANSIText.truncateToVisibleWidth(text, maxWidth: max(0, width))
    }

    private func visibleWidth(_ text: String) -> Int {
        PiTUIANSIText.visibleWidth(text)
    }
}
