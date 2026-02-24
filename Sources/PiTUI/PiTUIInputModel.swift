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
    private var killRing = PiKillRing()
    private var lastAction: LastAction?

    private var isInPaste = false
    private var pasteBuffer = ""

    private enum LastAction {
        case kill
        case yank
    }

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
        if PiTUIKeys.matchesKey(data, "ctrl+z") {
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
        if PiTUIKeys.matchesKey(data, "ctrl+w") || PiTUIKeys.matchesKey(data, "alt+backspace") {
            deleteWordBackward()
            return
        }
        if PiTUIKeys.matchesKey(data, "alt+d") {
            deleteWordForward()
            return
        }
        if PiTUIKeys.matchesKey(data, "ctrl+u") {
            deleteToLineStart()
            return
        }
        if PiTUIKeys.matchesKey(data, "ctrl+k") {
            deleteToLineEnd()
            return
        }
        if PiTUIKeys.matchesKey(data, "ctrl+y") {
            yank()
            return
        }
        if PiTUIKeys.matchesKey(data, "alt+y") {
            yankPop()
            return
        }
        if PiTUIKeys.matchesKey(data, "alt+left") {
            moveWordBackward()
            return
        }
        if PiTUIKeys.matchesKey(data, "alt+right") {
            moveWordForward()
            return
        }

        if containsControlCharacters(data) {
            return
        }
        insertText(data)
    }

    public func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        lastAction = nil
        pushUndo()
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: text, at: cursorIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16 + text.utf16.count, in: valueStorage)
    }

    public func handlePaste(_ text: String) {
        guard !text.isEmpty else { return }
        lastAction = nil
        pushUndo()
        let cleanText = text
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: cleanText, at: cursorIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16 + cleanText.utf16.count, in: valueStorage)
    }

    public func backspace() {
        guard cursorStorageUTF16 > 0 else { return }
        lastAction = nil
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
        lastAction = nil
        pushUndo()

        let nextIndex = valueStorage.index(after: cursorIndex)
        valueStorage.removeSubrange(cursorIndex..<nextIndex)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16, in: valueStorage)
    }

    public func moveCursorLeft() {
        guard cursorStorageUTF16 > 0 else { return }
        lastAction = nil
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        let prevIndex = valueStorage.index(before: cursorIndex)
        let removed = valueStorage[prevIndex..<cursorIndex]
        cursorStorageUTF16 -= String(removed).utf16.count
    }

    public func moveCursorRight() {
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        guard cursorIndex < valueStorage.endIndex else { return }
        lastAction = nil
        let nextIndex = valueStorage.index(after: cursorIndex)
        let moved = valueStorage[cursorIndex..<nextIndex]
        cursorStorageUTF16 += String(moved).utf16.count
    }

    public func moveCursorToStart() {
        lastAction = nil
        cursorStorageUTF16 = 0
    }

    public func moveCursorToEnd() {
        lastAction = nil
        cursorStorageUTF16 = valueStorage.utf16.count
    }

    public func undo() {
        guard let snapshot = undoStack.pop() else { return }
        valueStorage = snapshot.value
        cursorStorageUTF16 = clampCursor(snapshot.cursorUTF16, in: valueStorage)
        lastAction = nil
    }

    public func moveWordBackward() {
        guard cursorStorageUTF16 > 0 else { return }
        lastAction = nil

        while cursorStorageUTF16 > 0 {
            let previous = previousCharacterInfo()
            guard let previous else { break }
            if !Self.isWhitespace(previous.character) { break }
            cursorStorageUTF16 -= previous.utf16Count
        }

        while cursorStorageUTF16 > 0 {
            let previous = previousCharacterInfo()
            guard let previous else { break }
            if Self.isWhitespace(previous.character) { break }
            if Self.isPunctuation(previous.character) {
                repeat {
                    cursorStorageUTF16 -= previous.utf16Count
                } while cursorStorageUTF16 > 0 && (previousCharacterInfo().map { Self.isPunctuation($0.character) } ?? false)
                return
            }
            repeat {
                cursorStorageUTF16 -= previous.utf16Count
            } while cursorStorageUTF16 > 0 && {
                guard let p = previousCharacterInfo() else { return false }
                return !Self.isWhitespace(p.character) && !Self.isPunctuation(p.character)
            }()
            return
        }
    }

    public func moveWordForward() {
        guard cursorStorageUTF16 < valueStorage.utf16.count else { return }
        lastAction = nil

        while let next = currentCharacterInfo(), Self.isWhitespace(next.character) {
            cursorStorageUTF16 += next.utf16Count
        }

        guard let first = currentCharacterInfo() else { return }
        if Self.isPunctuation(first.character) {
            while let next = currentCharacterInfo(), Self.isPunctuation(next.character) {
                cursorStorageUTF16 += next.utf16Count
            }
            return
        }

        while let next = currentCharacterInfo(), !Self.isWhitespace(next.character), !Self.isPunctuation(next.character) {
            cursorStorageUTF16 += next.utf16Count
        }
    }

    public func deleteToLineStart() {
        guard cursorStorageUTF16 > 0 else { return }
        pushUndo()
        let deletedText = String(valueStorage[..<stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)])
        killRing.push(deletedText, options: .init(prepend: true, accumulate: lastAction == .kill))
        lastAction = .kill
        valueStorage = String(valueStorage[stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)...])
        cursorStorageUTF16 = 0
    }

    public func deleteToLineEnd() {
        guard cursorStorageUTF16 < valueStorage.utf16.count else { return }
        pushUndo()
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        let deletedText = String(valueStorage[cursorIndex...])
        killRing.push(deletedText, options: .init(prepend: false, accumulate: lastAction == .kill))
        lastAction = .kill
        valueStorage = String(valueStorage[..<cursorIndex])
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16, in: valueStorage)
    }

    public func deleteWordBackward() {
        guard cursorStorageUTF16 > 0 else { return }
        let wasKill = lastAction == .kill
        pushUndo()
        let oldCursor = cursorStorageUTF16
        moveWordBackward()
        let deleteFrom = cursorStorageUTF16
        cursorStorageUTF16 = oldCursor

        let deletedText = substringUTF16(from: deleteFrom, to: oldCursor)
        killRing.push(deletedText, options: .init(prepend: true, accumulate: wasKill))
        lastAction = .kill

        removeRangeUTF16(from: deleteFrom, to: oldCursor)
        cursorStorageUTF16 = deleteFrom
    }

    public func deleteWordForward() {
        guard cursorStorageUTF16 < valueStorage.utf16.count else { return }
        let wasKill = lastAction == .kill
        pushUndo()
        let oldCursor = cursorStorageUTF16
        moveWordForward()
        let deleteTo = cursorStorageUTF16
        cursorStorageUTF16 = oldCursor

        let deletedText = substringUTF16(from: oldCursor, to: deleteTo)
        killRing.push(deletedText, options: .init(prepend: false, accumulate: wasKill))
        lastAction = .kill

        removeRangeUTF16(from: oldCursor, to: deleteTo)
    }

    public func yank() {
        guard let text = killRing.peek() else { return }
        pushUndo()
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: text, at: cursorIndex)
        cursorStorageUTF16 += text.utf16.count
        lastAction = .yank
    }

    public func yankPop() {
        guard lastAction == .yank, killRing.length > 1 else { return }
        guard let previousText = killRing.peek() else { return }
        pushUndo()

        let start = cursorStorageUTF16 - previousText.utf16.count
        removeRangeUTF16(from: start, to: cursorStorageUTF16)
        cursorStorageUTF16 = start

        killRing.rotate()
        guard let nextText = killRing.peek() else { return }
        let cursorIndex = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        valueStorage.insert(contentsOf: nextText, at: cursorIndex)
        cursorStorageUTF16 += nextText.utf16.count
        lastAction = .yank
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

    func currentCharacterInfo() -> (character: Character, utf16Count: Int)? {
        let index = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        guard index < valueStorage.endIndex else { return nil }
        let next = valueStorage.index(after: index)
        let char = valueStorage[index]
        return (char, String(valueStorage[index..<next]).utf16.count)
    }

    func previousCharacterInfo() -> (character: Character, utf16Count: Int)? {
        let index = stringIndex(forUTF16Offset: cursorStorageUTF16, in: valueStorage)
        guard index > valueStorage.startIndex else { return nil }
        let prev = valueStorage.index(before: index)
        let char = valueStorage[prev]
        return (char, String(valueStorage[prev..<index]).utf16.count)
    }

    func substringUTF16(from start: Int, to end: Int) -> String {
        let s = stringIndex(forUTF16Offset: start, in: valueStorage)
        let e = stringIndex(forUTF16Offset: end, in: valueStorage)
        return String(valueStorage[s..<e])
    }

    func removeRangeUTF16(from start: Int, to end: Int) {
        let s = stringIndex(forUTF16Offset: start, in: valueStorage)
        let e = stringIndex(forUTF16Offset: end, in: valueStorage)
        valueStorage.removeSubrange(s..<e)
        cursorStorageUTF16 = clampCursor(cursorStorageUTF16, in: valueStorage)
    }

    static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }
}
