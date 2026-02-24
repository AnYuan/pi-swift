import Foundation

public protocol PiTUIInteractiveComponent: PiTUIComponent {
    func handleInput(_ data: String)
}

public typealias PiTUISettingsSubmenuFactory = (
    _ currentValue: String,
    _ done: @escaping (String?) -> Void
) -> PiTUIInteractiveComponent

public struct PiTUISettingItem: Equatable {
    public var id: String
    public var label: String
    public var description: String?
    public var currentValue: String
    public var values: [String]?
    public var submenu: PiTUISettingsSubmenuFactory?

    public init(
        id: String,
        label: String,
        description: String? = nil,
        currentValue: String,
        values: [String]? = nil,
        submenu: PiTUISettingsSubmenuFactory? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.currentValue = currentValue
        self.values = values
        self.submenu = submenu
    }

    public static func == (lhs: PiTUISettingItem, rhs: PiTUISettingItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.label == rhs.label &&
            lhs.description == rhs.description &&
            lhs.currentValue == rhs.currentValue &&
            lhs.values == rhs.values
    }
}

public struct PiTUISettingsListTheme: @unchecked Sendable {
    public var label: (String, Bool) -> String
    public var value: (String, Bool) -> String
    public var description: (String) -> String
    public var cursor: String
    public var hint: (String) -> String

    public init(
        label: @escaping (String, Bool) -> String,
        value: @escaping (String, Bool) -> String,
        description: @escaping (String) -> String,
        cursor: String,
        hint: @escaping (String) -> String
    ) {
        self.label = label
        self.value = value
        self.description = description
        self.cursor = cursor
        self.hint = hint
    }

    public static let plain = PiTUISettingsListTheme(
        label: { text, _ in text },
        value: { text, _ in text },
        description: { $0 },
        cursor: "→ ",
        hint: { $0 }
    )
}

public struct PiTUISettingsListOptions: Equatable, Sendable {
    public var enableSearch: Bool

    public init(enableSearch: Bool = false) {
        self.enableSearch = enableSearch
    }
}

public final class PiTUISettingsList: PiTUIComponent {
    private var items: [PiTUISettingItem]
    private var filteredIndices: [Int]
    private var selectedIndex: Int = 0
    private let maxVisible: Int
    private let theme: PiTUISettingsListTheme
    private let options: PiTUISettingsListOptions
    private var searchQuery: String = ""
    private var submenuComponent: PiTUIInteractiveComponent?
    private var submenuItemFilteredIndex: Int?

    public var onChange: ((String, String) -> Void)?
    public var onCancel: (() -> Void)?

    public init(
        items: [PiTUISettingItem],
        maxVisible: Int = 8,
        theme: PiTUISettingsListTheme = .plain,
        options: PiTUISettingsListOptions = .init()
    ) {
        self.items = items
        self.filteredIndices = Array(items.indices)
        self.maxVisible = max(1, maxVisible)
        self.theme = theme
        self.options = options
        applyFilter()
    }

    public func invalidate() {}

    public func setItems(_ items: [PiTUISettingItem]) {
        self.items = items
        applyFilter()
    }

    public func updateValue(id: String, newValue: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].currentValue = newValue
        applyFilter(keepSelectionItemID: id)
    }

    public func getSearchQuery() -> String {
        searchQuery
    }

    public func getSelectedItem() -> PiTUISettingItem? {
        guard let itemIndex = filteredIndices[safe: selectedIndex] else { return nil }
        return items[itemIndex]
    }

    public func render(width: Int) -> [String] {
        if let submenuComponent {
            return submenuComponent.render(width: width)
        }

        let width = max(1, width)
        var lines: [String] = []

        if options.enableSearch {
            lines.append(theme.hint(truncate("  Search: \(searchQuery)", width: width)))
            lines.append("")
        }

        if items.isEmpty {
            lines.append(theme.hint(truncate("  No settings available", width: width)))
            appendHintLine(into: &lines, width: width)
            return lines
        }

        if filteredIndices.isEmpty {
            lines.append(theme.hint(truncate("  No matching settings", width: width)))
            appendHintLine(into: &lines, width: width)
            return lines
        }

        let startIndex = max(0, min(selectedIndex - (maxVisible / 2), filteredIndices.count - maxVisible))
        let endIndex = min(startIndex + maxVisible, filteredIndices.count)
        let maxLabelWidth = min(30, items.map { visibleWidth($0.label) }.max() ?? 0)

        for i in startIndex..<endIndex {
            let item = items[filteredIndices[i]]
            let isSelected = i == selectedIndex
            let prefix = isSelected ? theme.cursor : "  "
            let prefixWidth = visibleWidth(prefix)
            let paddedLabel = item.label + String(repeating: " ", count: max(0, maxLabelWidth - visibleWidth(item.label)))
            let label = theme.label(paddedLabel, isSelected)
            let separator = "  "
            let used = prefixWidth + maxLabelWidth + visibleWidth(separator)
            let valueWidth = max(0, width - used)
            let value = theme.value(truncate(item.currentValue, width: valueWidth), isSelected)
            lines.append(truncate(prefix + label + separator + value, width: width))
        }

        if startIndex > 0 || endIndex < filteredIndices.count {
            lines.append(theme.hint(truncate("  (\(selectedIndex + 1)/\(filteredIndices.count))", width: width)))
        }

        if let selected = getSelectedItem(), let description = selected.description, !description.isEmpty {
            lines.append("")
            for wrapped in wrapLines(normalizeSingleLine(description), width: max(1, width - 2)) {
                lines.append(theme.description("  " + wrapped))
            }
        }

        appendHintLine(into: &lines, width: width)
        return lines
    }

    public func handleInput(_ data: String) {
        if let submenuComponent {
            submenuComponent.handleInput(data)
            return
        }

        let kb = PiTUIEditorKeybindings.get()

        if kb.matches(data, action: .selectUp) {
            guard !filteredIndices.isEmpty else { return }
            selectedIndex = selectedIndex == 0 ? filteredIndices.count - 1 : selectedIndex - 1
            return
        }
        if kb.matches(data, action: .selectDown) {
            guard !filteredIndices.isEmpty else { return }
            selectedIndex = selectedIndex == filteredIndices.count - 1 ? 0 : selectedIndex + 1
            return
        }
        if kb.matches(data, action: .selectCancel) {
            onCancel?()
            return
        }
        if kb.matches(data, action: .selectConfirm) || PiTUIKeys.matchesKey(data, "space") {
            activateSelectedItem()
            return
        }

        guard options.enableSearch else { return }
        handleSearchInput(data)
    }

    private func activateSelectedItem() {
        guard let itemIndex = filteredIndices[safe: selectedIndex] else { return }
        if let submenuFactory = items[itemIndex].submenu {
            submenuItemFilteredIndex = selectedIndex
            let currentValue = items[itemIndex].currentValue
            submenuComponent = submenuFactory(currentValue) { [weak self] selectedValue in
                guard let self else { return }
                if let selectedValue {
                    self.items[itemIndex].currentValue = selectedValue
                    self.onChange?(self.items[itemIndex].id, selectedValue)
                }
                self.submenuComponent = nil
                if let submenuItemFilteredIndex = self.submenuItemFilteredIndex {
                    self.selectedIndex = max(0, min(submenuItemFilteredIndex, max(0, self.filteredIndices.count - 1)))
                }
                self.submenuItemFilteredIndex = nil
            }
            return
        }

        guard let values = items[itemIndex].values, !values.isEmpty else { return }

        let currentValue = items[itemIndex].currentValue
        let currentIdx = values.firstIndex(of: currentValue) ?? -1
        let nextIdx = (currentIdx + 1) % values.count
        let newValue = values[nextIdx]
        items[itemIndex].currentValue = newValue
        onChange?(items[itemIndex].id, newValue)
    }

    private func handleSearchInput(_ data: String) {
        if PiTUIKeys.matchesKey(data, "backspace") {
            guard !searchQuery.isEmpty else { return }
            searchQuery.removeLast()
            applyFilter()
            return
        }

        guard let key = PiTUIKeys.parseKey(data) else { return }
        if key.count == 1, let ch = key.first, !ch.isWhitespace, !ch.isNewline {
            searchQuery.append(ch)
            applyFilter()
        }
    }

    private func applyFilter(keepSelectionItemID: String? = nil) {
        let previousID = keepSelectionItemID
        if options.enableSearch, !searchQuery.isEmpty {
            let needle = searchQuery.lowercased()
            filteredIndices = items.indices.filter { idx in
                items[idx].label.lowercased().contains(needle) || items[idx].id.lowercased().contains(needle)
            }
        } else {
            filteredIndices = Array(items.indices)
        }

        if let previousID,
           let newFilteredIndex = filteredIndices.firstIndex(where: { items[$0].id == previousID }) {
            selectedIndex = newFilteredIndex
        } else {
            selectedIndex = 0
        }

        if !filteredIndices.isEmpty {
            selectedIndex = max(0, min(selectedIndex, filteredIndices.count - 1))
        } else {
            selectedIndex = 0
        }
    }

    private func appendHintLine(into lines: inout [String], width: Int) {
        lines.append("")
        let hint = options.enableSearch
            ? "  Type to search · Enter/Space to change · Esc to cancel"
            : "  Enter/Space to change · Esc to cancel"
        lines.append(theme.hint(truncate(hint, width: width)))
    }

    private func truncate(_ text: String, width: Int) -> String {
        PiTUIANSIText.truncateToVisibleWidth(text, maxWidth: max(0, width))
    }

    private func visibleWidth(_ text: String) -> Int {
        PiTUIANSIText.visibleWidth(text)
    }

    private func normalizeSingleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private func wrapLines(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [""] }
        guard !text.isEmpty else { return [""] }

        var result: [String] = []
        var current = ""

        for word in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            if current.isEmpty {
                current = truncate(word, width: width)
                continue
            }

            let candidate = current + " " + word
            if visibleWidth(candidate) <= width {
                current = candidate
            } else {
                result.append(current)
                current = truncate(word, width: width)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result.isEmpty ? [""] : result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension PiTUIInputComponent: PiTUIInteractiveComponent {}
extension PiTUIEditorComponent: PiTUIInteractiveComponent {}
