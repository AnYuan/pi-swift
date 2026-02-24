import Foundation

public struct PiTUIAutocompleteItem: Equatable, Sendable {
    public var value: String
    public var label: String
    public var description: String?

    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

public struct PiTUIAutocompleteSuggestions: Equatable, Sendable {
    public var items: [PiTUIAutocompleteItem]
    public var prefix: String
}

public struct PiTUIAutocompleteApplyResult: Equatable, Sendable {
    public var lines: [String]
    public var cursorLine: Int
    public var cursorCol: Int
}

public final class PiTUICombinedAutocompleteProvider {
    private let basePath: String
    private let fileManager: FileManager

    public init(basePath: String = FileManager.default.currentDirectoryPath, fileManager: FileManager = .default) {
        self.basePath = basePath
        self.fileManager = fileManager
    }

    public func getForceFileSuggestions(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int
    ) -> PiTUIAutocompleteSuggestions? {
        let currentLine = lines[safe: cursorLine] ?? ""
        let textBeforeCursor = String(currentLine.prefix(max(0, cursorCol)))

        let trimmed = textBeforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") && !trimmed.contains(" ") {
            return nil // slash command, not file path completion
        }

        guard let prefix = extractPathPrefix(textBeforeCursor, forceExtract: true) else {
            return nil
        }
        let items = getFileSuggestions(prefix: prefix)
        guard !items.isEmpty else { return nil }
        return .init(items: items, prefix: prefix)
    }

    public func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: PiTUIAutocompleteItem,
        prefix: String
    ) -> PiTUIAutocompleteApplyResult {
        var newLines = lines
        let currentLine = lines[safe: cursorLine] ?? ""
        let safeCursorCol = max(0, min(cursorCol, currentLine.count))

        let beforePrefixCount = max(0, safeCursorCol - prefix.count)
        let beforePrefix = String(currentLine.prefix(beforePrefixCount))
        let afterCursor = String(currentLine.dropFirst(safeCursorCol))

        let isQuotedPrefix = prefix.hasPrefix("\"") || prefix.hasPrefix("@\"")
        let adjustedAfterCursor: String = {
            if isQuotedPrefix && item.value.hasSuffix("\"") && afterCursor.hasPrefix("\"") {
                return String(afterCursor.dropFirst())
            }
            return afterCursor
        }()

        let isAttachment = prefix.hasPrefix("@")
        let isDirectory = item.label.hasSuffix("/")
        let suffix = (isAttachment && !isDirectory) ? " " : ""

        let newLine = beforePrefix + item.value + suffix + adjustedAfterCursor
        if newLines.indices.contains(cursorLine) {
            newLines[cursorLine] = newLine
        } else {
            while newLines.count < cursorLine {
                newLines.append("")
            }
            newLines.append(newLine)
        }

        let hasTrailingQuote = item.value.hasSuffix("\"")
        let cursorOffset = isDirectory && hasTrailingQuote ? max(0, item.value.count - 1) : item.value.count

        return .init(
            lines: newLines,
            cursorLine: cursorLine,
            cursorCol: beforePrefix.count + cursorOffset + suffix.count
        )
    }

    private func getFileSuggestions(prefix: String) -> [PiTUIAutocompleteItem] {
        let parsed = parsePathPrefix(prefix)
        let rawPrefix = parsed.rawPrefix
        let expandedPrefix = expandHomePath(rawPrefix)

        let searchDir: String
        let searchPrefix: String
        let displayPrefix = rawPrefix

        let isRootPrefix = rawPrefix.isEmpty || rawPrefix == "./" || rawPrefix == "../" || rawPrefix == "~" ||
            rawPrefix == "~/" || rawPrefix == "/" || (parsed.isAtPrefix && rawPrefix.isEmpty)

        if isRootPrefix || rawPrefix.hasSuffix("/") {
            searchDir = resolveSearchDir(prefix: rawPrefix, expandedPrefix: expandedPrefix)
            searchPrefix = ""
        } else {
            let ns = expandedPrefix as NSString
            let dir = ns.deletingLastPathComponent
            let file = ns.lastPathComponent
            searchDir = resolveSearchDir(prefix: dir.isEmpty ? "." : dir, expandedPrefix: dir.isEmpty ? "." : dir)
            searchPrefix = file
        }

        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: searchDir)
        } catch {
            return []
        }

        var suggestions: [PiTUIAutocompleteItem] = []
        for name in contents {
            guard name.lowercased().hasPrefix(searchPrefix.lowercased()) else { continue }
            let fullPath = (searchDir as NSString).appendingPathComponent(name)
            var isDirFlag: ObjCBool = false
            let exists = fileManager.fileExists(atPath: fullPath, isDirectory: &isDirFlag)
            guard exists else { continue }
            let isDirectory = isDirFlag.boolValue

            let relativePath: String
            if displayPrefix.hasSuffix("/") {
                relativePath = displayPrefix + name
            } else if displayPrefix.contains("/") {
                relativePath = rebuildPathWithDisplayPrefix(displayPrefix: displayPrefix, entryName: name)
            } else if displayPrefix.hasPrefix("~") {
                relativePath = "~/" + name
            } else {
                relativePath = name
            }

            let pathValue = isDirectory ? relativePath + "/" : relativePath
            suggestions.append(.init(
                value: buildCompletionValue(pathValue, isDirectory: isDirectory, isAtPrefix: parsed.isAtPrefix, isQuotedPrefix: parsed.isQuotedPrefix),
                label: name + (isDirectory ? "/" : "")
            ))
        }

        suggestions.sort { lhs, rhs in
            let lhsDir = lhs.label.hasSuffix("/")
            let rhsDir = rhs.label.hasSuffix("/")
            if lhsDir != rhsDir { return lhsDir && !rhsDir }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

        return suggestions
    }

    private func resolveSearchDir(prefix: String, expandedPrefix: String) -> String {
        if prefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
            return expandedPrefix
        }
        return (basePath as NSString).appendingPathComponent(expandedPrefix)
    }

    private func rebuildPathWithDisplayPrefix(displayPrefix: String, entryName: String) -> String {
        if displayPrefix.hasPrefix("~/") {
            let homeRelative = String(displayPrefix.dropFirst(2))
            let dir = (homeRelative as NSString).deletingLastPathComponent
            return dir == "." || dir.isEmpty ? "~/" + entryName : "~/" + (dir as NSString).appendingPathComponent(entryName)
        }
        if displayPrefix.hasPrefix("/") {
            let dir = (displayPrefix as NSString).deletingLastPathComponent
            if dir == "/" { return "/" + entryName }
            return (dir as NSString).appendingPathComponent(entryName)
        }
        let dir = (displayPrefix as NSString).deletingLastPathComponent
        if dir == "." || dir.isEmpty { return entryName }
        return (dir as NSString).appendingPathComponent(entryName)
    }

    private func expandHomePath(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = NSHomeDirectory()
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return (home as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return path
    }

    private func extractPathPrefix(_ text: String, forceExtract: Bool) -> String? {
        if let quoted = extractQuotedPrefix(text) {
            return quoted
        }
        let pathPrefix = tokenAfterLastDelimiter(in: text)
        if forceExtract {
            return pathPrefix
        }
        if pathPrefix.contains("/") || pathPrefix.hasPrefix(".") || pathPrefix.hasPrefix("~/") {
            return pathPrefix
        }
        if pathPrefix.isEmpty && text.hasSuffix(" ") {
            return pathPrefix
        }
        return nil
    }

    private func extractQuotedPrefix(_ text: String) -> String? {
        guard let quoteStart = findUnclosedQuoteStart(in: text) else { return nil }

        if quoteStart > 0, text[text.index(text.startIndex, offsetBy: quoteStart - 1)] == "@" {
            if !isTokenStart(text, at: quoteStart - 1) { return nil }
            let start = text.index(text.startIndex, offsetBy: quoteStart - 1)
            return String(text[start...])
        }

        if !isTokenStart(text, at: quoteStart) { return nil }
        let start = text.index(text.startIndex, offsetBy: quoteStart)
        return String(text[start...])
    }

    private func findUnclosedQuoteStart(in text: String) -> Int? {
        var inQuotes = false
        var quoteStart = -1
        for (idx, ch) in text.enumerated() where ch == "\"" {
            inQuotes.toggle()
            if inQuotes { quoteStart = idx }
        }
        return inQuotes ? quoteStart : nil
    }

    private func isTokenStart(_ text: String, at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = text[text.index(text.startIndex, offsetBy: index - 1)]
        return Self.pathDelimiters.contains(previous)
    }

    private func tokenAfterLastDelimiter(in text: String) -> String {
        guard let idx = text.lastIndex(where: { Self.pathDelimiters.contains($0) }) else {
            return text
        }
        return String(text[text.index(after: idx)...])
    }

    private func parsePathPrefix(_ prefix: String) -> (rawPrefix: String, isAtPrefix: Bool, isQuotedPrefix: Bool) {
        if prefix.hasPrefix("@\"") {
            return (String(prefix.dropFirst(2)), true, true)
        }
        if prefix.hasPrefix("\"") {
            return (String(prefix.dropFirst(1)), false, true)
        }
        if prefix.hasPrefix("@") {
            return (String(prefix.dropFirst(1)), true, false)
        }
        return (prefix, false, false)
    }

    private func buildCompletionValue(_ path: String, isDirectory: Bool, isAtPrefix: Bool, isQuotedPrefix: Bool) -> String {
        let needsQuotes = isQuotedPrefix || path.contains(" ")
        let at = isAtPrefix ? "@" : ""
        if !needsQuotes {
            return at + path
        }
        return at + "\"" + path + "\""
    }

    private static let pathDelimiters: Set<Character> = [" ", "\t", "\"", "'", "="]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
