import Foundation

public final class PiTUIInputModel {
    private struct Snapshot {
        var value: String
        var cursorUTF16: Int
    }

    private static let pasteStart = "\u{001B}[200~"
    private static let pasteEnd = "\u{001B}[201~"

    private var valueStorage = ""
    private var cursorStorageUTF16 = 0
    private var undoStack = PiUndoStack<Snapshot>()

    private var isInPaste = false
    private var pasteBuffer = ""

    public init(value: String = "") {
        valueStorage = value
        cursorStorageUTF16 = value.utf16.count
    }

    public var value: String {
        valueStorage
    }

    public var cursorUTF16: Int {
        cursorStorageUTF16
    }

    public func setValue(_ value: String) {
        valueStorage = value
        cursorStorageUTF16 = min(cursorStorageUTF16, value.utf16.count)
        isInPaste = false
        pasteBuffer = ""
    }

    public func setCursorUTF16(_ offset: Int) {
        cursorStorageUTF16 = clampCursor(offset, in: valueStorage)
    }

    public func handleInput(_ data: String) {
        var data = data

        if data.contains(Self.pasteStart) {
            isInPaste = true
            pasteBuffer = ""
            data = data.replacingOccurrences(of: Self.pasteStart, with: "")
        }

        if isInPaste {
            pasteBuffer += data
            if let endRange = pasteBuffer.range(of: Self.pasteEnd) {
                let pasted = String(pasteBuffer[..<endRange.lowerBound])
                let remaining = String(pasteBuffer[endRange.upperBound...])
                handlePaste(pasted)
                isInPaste = false
                pasteBuffer = ""
                if !remaining.isEmpty {
                    handleInput(remaining)
                }
            }
            return
        }

        if PiTUIKeys.matchesKey(data, "undo") || data == "\u{001A}" {
            undo()
            return
        }
        if PiTUIKeys.matchesKey(data, "cursorLeft") || PiTUIKeys.matchesKey(data, "left") {
            moveCursorLeft()
            return
        }
        if PiTUIKeys.matchesKey(data, "cursorRight") || PiTUIKeys.matchesKey(data, "right") {
            moveCursorRight()
            return
        }
        if PiTUIKeys.matchesKey(data, "cursorLineStart") || PiTUIKeys.matchesKey(data, "home") || PiTUIKeys.matchesKey(data, "ctrl+a") {
            moveCursorToStart()
            return
        }
        if PiTUIKeys.matchesKey(data, "cursorLineEnd") || PiTUIKeys.matchesKey(data, "end") || PiTUIKeys.matchesKey(data, "ctrl+e") {
            moveCursorToEnd()
            return
        }
        if PiTUIKeys.matchesKey(data, "deleteCharBackward") || PiTUIKeys.matchesKey(data, "backspace") {
            backspace()
            return
        }
        if data == "\u{001B}[3~" {
            deleteForward()
            return
        }

        if containsControlCharacters(data) {
            return
        }
        insertText(data)
    }

    public func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        pushUndo()
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: text, at: cursorIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16 + text.utf16.count, in: valueStorage)
    }

    public func handlePaste(_ text: String) {
        guard !text.isEmpty else { return }
        pushUndo()
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: text, at: cursorIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16 + text.utf16.count, in: valueStorage)
    }

    public func backspace() {
        guard cursorStorageUTF16 > 0 else { return }
        pushUndo()

        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        let prevIndex = valueStorage.index(before: cursorIndex)
        let charRange = prevIndex..<cursorIndex
        let removed = valueStorage[charRange]
        valueStorage.removeSubrange(charRange)
        cursorStorageUTF16 -= String(removed).utf16.count
    }

    public func deleteForward() {
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        guard cursorIndex < valueStorage.endIndex else { return }
        pushUndo()

        let nextIndex = valueStorage.index(after: cursorIndex)
        valueStorage.removeSubrange(cursorIndex..<nextIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16, in: valueStorage)
    }

    public func moveCursorLeft() {
        guard cursorStorageUTF16 > 0 else { return }
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        let prevIndex = valueStorage.index(before: cursorIndex)
        let removed = valueStorage[prevIndex..<cursorIndex]
        cursorStorageUTF16 -= String(removed).utf16.count
    }

    public func moveCursorRight() {
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        guard cursorIndex < valueStorage.endIndex else { return }
        let nextIndex = valueStorage.index(after: cursorIndex)
        let moved = valueStorage[cursorIndex..<nextIndex]
        cursorStorageUTF16 += String(moved).utf16.count
    }

    public func moveCursorToStart() {
        cursorStorageUTF16 = 0
    }

    public func moveCursorToEnd() {
        cursorStorageUTF16 = valueStorage.utf16.count
    }

    public func undo() {
        guard let snapshot = undoStack.pop() else { return }
        valueStorage = snapshot.value
        cursorStorageUTF16 = clampCursor(snapshot.cursorUTF16, in: valueStorage)
    }

    private func pushUndo() {
        undoStack.push(.init(value: valueStorage, cursorUTF16: cursorStorageUTF16))
    }

    private func containsControlCharacters(_ data: String) -> Bool {
        data.unicodeScalars.contains { scalar in
            let v = scalar.value
            return v < 32 || v == 0x7F || (v >= 0x80 && v <= 0x9F)
        }
    }
}

private extension PiTUIInputModel {
    func clampCursor(_ offset: Int, in string: String) -> Int {
        max(0, min(offset, string.utf16.count))
    }

    func stringIndex(forUTF16Offset offset: Int, in string: String) -> String.Index {
        let clamped = clampCursor(offset, in: string)
        let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: string) ?? string.endIndex
    }
}
