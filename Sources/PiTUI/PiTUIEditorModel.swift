public final class PiTUIEditorModel {
    public struct CursorPosition: Equatable {
        public var line: Int
        public var colUTF16: Int

        public init(line: Int, colUTF16: Int) {
            self.line = line
            self.colUTF16 = colUTF16
        }
    }

    private struct Snapshot {
        var lines: [String]
        var cursor: CursorPosition
    }

    private var undoStack = PiUndoStack<Snapshot>()
    private(set) public var lines: [String] = [""]
    private var cursor = CursorPosition(line: 0, colUTF16: 0)

    public init() {}

    public var cursorPosition: CursorPosition {
        cursor
    }

    public func getText() -> String {
        lines.joined(separator: "\n")
    }

    public func setText(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let split = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines = split.isEmpty ? [""] : split
        cursor.line = max(0, lines.count - 1)
        cursor.colUTF16 = lines[cursor.line].utf16.count
    }

    public func setCursor(line: Int, colUTF16: Int) {
        guard !lines.isEmpty else {
            lines = [""]
            cursor = .init(line: 0, colUTF16: 0)
            return
        }
        let clampedLine = max(0, min(line, lines.count - 1))
        cursor.line = clampedLine
        cursor.colUTF16 = clampCol(colUTF16, inLine: clampedLine)
    }

    public func insertTextAtCursor(_ text: String) {
        guard !text.isEmpty else { return }
        pushUndo()

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let current = currentLine
        let splitIndex = stringIndex(in: current, utf16Offset: cursor.colUTF16)
        let before = String(current[..<splitIndex])
        let after = String(current[splitIndex...])

        let parts = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.count <= 1 {
            lines[cursor.line] = before + normalized + after
            cursor.colUTF16 += normalized.utf16.count
            return
        }

        var newLines: [String] = []
        newLines.append(before + (parts.first ?? ""))
        if parts.count > 2 {
            newLines.append(contentsOf: parts.dropFirst().dropLast())
        }
        newLines.append((parts.last ?? "") + after)

        lines.replaceSubrange(cursor.line...cursor.line, with: newLines)
        cursor.line += newLines.count - 1
        cursor.colUTF16 = (parts.last ?? "").utf16.count
    }

    public func insertNewline() {
        pushUndo()
        let line = currentLine
        let splitIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
        let before = String(line[..<splitIndex])
        let after = String(line[splitIndex...])
        lines[cursor.line] = before
        lines.insert(after, at: cursor.line + 1)
        cursor.line += 1
        cursor.colUTF16 = 0
    }

    public func backspace() {
        if cursor.colUTF16 > 0 {
            pushUndo()
            let line = currentLine
            let cursorIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
            let prevIndex = line.index(before: cursorIndex)
            let removed = String(line[prevIndex..<cursorIndex])
            lines[cursor.line] = String(line[..<prevIndex]) + String(line[cursorIndex...])
            cursor.colUTF16 -= removed.utf16.count
            return
        }

        guard cursor.line > 0 else { return }
        pushUndo()
        let previous = lines[cursor.line - 1]
        let current = lines[cursor.line]
        let previousLen = previous.utf16.count
        lines[cursor.line - 1] = previous + current
        lines.remove(at: cursor.line)
        cursor.line -= 1
        cursor.colUTF16 = previousLen
    }

    public func deleteForward() {
        let line = currentLine
        let cursorIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
        if cursorIndex < line.endIndex {
            pushUndo()
            let nextIndex = line.index(after: cursorIndex)
            lines[cursor.line] = String(line[..<cursorIndex]) + String(line[nextIndex...])
            cursor.colUTF16 = clampCol(cursor.colUTF16, inLine: cursor.line)
            return
        }

        guard cursor.line < lines.count - 1 else { return }
        pushUndo()
        lines[cursor.line] = line + lines[cursor.line + 1]
        lines.remove(at: cursor.line + 1)
    }

    public func moveCursorLeft() {
        if cursor.colUTF16 > 0 {
            let line = currentLine
            let cursorIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
            let prevIndex = line.index(before: cursorIndex)
            let moved = String(line[prevIndex..<cursorIndex])
            cursor.colUTF16 -= moved.utf16.count
            return
        }
        guard cursor.line > 0 else { return }
        cursor.line -= 1
        cursor.colUTF16 = lines[cursor.line].utf16.count
    }

    public func moveCursorRight() {
        let line = currentLine
        let cursorIndex = stringIndex(in: line, utf16Offset: cursor.colUTF16)
        if cursorIndex < line.endIndex {
            let nextIndex = line.index(after: cursorIndex)
            let moved = String(line[cursorIndex..<nextIndex])
            cursor.colUTF16 += moved.utf16.count
            return
        }
        guard cursor.line < lines.count - 1 else { return }
        cursor.line += 1
        cursor.colUTF16 = 0
    }

    public func moveCursorUp() {
        guard cursor.line > 0 else { return }
        cursor.line -= 1
        cursor.colUTF16 = clampCol(cursor.colUTF16, inLine: cursor.line)
    }

    public func moveCursorDown() {
        guard cursor.line < lines.count - 1 else { return }
        cursor.line += 1
        cursor.colUTF16 = clampCol(cursor.colUTF16, inLine: cursor.line)
    }

    public func undo() {
        guard let snapshot = undoStack.pop() else { return }
        lines = snapshot.lines.isEmpty ? [""] : snapshot.lines
        cursor = snapshot.cursor
        cursor.line = max(0, min(cursor.line, lines.count - 1))
        cursor.colUTF16 = clampCol(cursor.colUTF16, inLine: cursor.line)
    }

    private var currentLine: String {
        lines[cursor.line]
    }

    private func pushUndo() {
        undoStack.push(.init(lines: lines, cursor: cursor))
    }

    private func clampCol(_ colUTF16: Int, inLine line: Int) -> Int {
        max(0, min(colUTF16, lines[line].utf16.count))
    }

    private func stringIndex(in string: String, utf16Offset: Int) -> String.Index {
        let clamped = max(0, min(utf16Offset, string.utf16.count))
        let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: string) ?? string.endIndex
    }
}
