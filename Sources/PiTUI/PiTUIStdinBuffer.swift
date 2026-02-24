import Foundation

public final class PiTUIStdinBuffer {
    public typealias DataHandler = (String) -> Void
    public typealias PasteHandler = (String) -> Void

    private static let esc = "\u{001B}"
    private static let bracketedPasteStart = "\u{001B}[200~"
    private static let bracketedPasteEnd = "\u{001B}[201~"

    private var buffer = ""
    private var pasteMode = false
    private var pasteBuffer = ""
    private var dataHandlers: [DataHandler] = []
    private var pasteHandlers: [PasteHandler] = []

    public init() {}

    public func onData(_ handler: @escaping DataHandler) {
        dataHandlers.append(handler)
    }

    public func onPaste(_ handler: @escaping PasteHandler) {
        pasteHandlers.append(handler)
    }

    public func process(_ data: String) {
        if data.isEmpty && buffer.isEmpty {
            emitData("")
            return
        }

        buffer += data

        if pasteMode {
            pasteBuffer += buffer
            buffer = ""
            tryFinishPasteMode()
            return
        }

        if let startRange = buffer.range(of: Self.bracketedPasteStart) {
            let beforePaste = String(buffer[..<startRange.lowerBound])
            if !beforePaste.isEmpty {
                let result = Self.extractCompleteSequences(beforePaste)
                result.sequences.forEach(emitData)
            }

            buffer = String(buffer[startRange.upperBound...])
            pasteMode = true
            pasteBuffer = buffer
            buffer = ""
            tryFinishPasteMode()
            return
        }

        let result = Self.extractCompleteSequences(buffer)
        buffer = result.remainder
        result.sequences.forEach(emitData)
    }

    public func process(_ data: Data) {
        if data.count == 1, let byte = data.first, byte > 127 {
            let converted = byte - 128
            process("\u{001B}" + String(UnicodeScalar(Int(converted))!))
            return
        }

        process(String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    public func flush() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let flushed = [buffer]
        buffer = ""
        return flushed
    }

    public func clear() {
        buffer = ""
        pasteMode = false
        pasteBuffer = ""
    }

    public func getBuffer() -> String {
        buffer
    }

    public func destroy() {
        clear()
    }

    private func tryFinishPasteMode() {
        guard pasteMode else { return }
        guard let endRange = pasteBuffer.range(of: Self.bracketedPasteEnd) else { return }

        let pastedContent = String(pasteBuffer[..<endRange.lowerBound])
        let remaining = String(pasteBuffer[endRange.upperBound...])

        pasteMode = false
        pasteBuffer = ""
        emitPaste(pastedContent)

        if !remaining.isEmpty {
            process(remaining)
        }
    }

    private func emitData(_ value: String) {
        dataHandlers.forEach { $0(value) }
    }

    private func emitPaste(_ value: String) {
        pasteHandlers.forEach { $0(value) }
    }
}

private extension PiTUIStdinBuffer {
    enum SequenceStatus {
        case complete
        case incomplete
        case notEscape
    }

    static func extractCompleteSequences(_ input: String) -> (sequences: [String], remainder: String) {
        var sequences: [String] = []
        var pos = input.startIndex

        while pos < input.endIndex {
            let remaining = String(input[pos...])

            if remaining.hasPrefix(esc) {
                var seqEnd = 1
                var completed = false

                while seqEnd <= remaining.count {
                    let candidate = String(remaining.prefix(seqEnd))
                    switch isCompleteSequence(candidate) {
                    case .complete:
                        sequences.append(candidate)
                        pos = input.index(pos, offsetBy: seqEnd)
                        completed = true
                    case .incomplete:
                        seqEnd += 1
                    case .notEscape:
                        sequences.append(candidate)
                        pos = input.index(pos, offsetBy: seqEnd)
                        completed = true
                    }

                    if completed { break }
                }

                if !completed {
                    return (sequences, remaining)
                }
            } else {
                let next = input.index(after: pos)
                sequences.append(String(input[pos..<next]))
                pos = next
            }
        }

        return (sequences, "")
    }

    static func isCompleteSequence(_ data: String) -> SequenceStatus {
        guard data.hasPrefix(esc) else { return .notEscape }
        guard data.count > 1 else { return .incomplete }

        let afterEsc = String(data.dropFirst())

        if afterEsc.hasPrefix("[") {
            if afterEsc.hasPrefix("[M") {
                return data.count >= 6 ? .complete : .incomplete
            }
            return isCompleteCsiSequence(data)
        }

        if afterEsc.hasPrefix("]") {
            return (data.hasSuffix("\u{001B}\\") || data.hasSuffix("\u{0007}")) ? .complete : .incomplete
        }

        if afterEsc.hasPrefix("P") || afterEsc.hasPrefix("_") {
            return data.hasSuffix("\u{001B}\\") ? .complete : .incomplete
        }

        if afterEsc.hasPrefix("O") {
            return afterEsc.count >= 2 ? .complete : .incomplete
        }

        return afterEsc.count == 1 ? .complete : .complete
    }

    static func isCompleteCsiSequence(_ data: String) -> SequenceStatus {
        guard data.hasPrefix("\u{001B}[") else { return .complete }
        guard data.count >= 3 else { return .incomplete }

        let payload = String(data.dropFirst(2))
        guard let last = payload.unicodeScalars.last else { return .incomplete }
        guard last.value >= 0x40 && last.value <= 0x7E else { return .incomplete }

        if payload.hasPrefix("<") {
            if payload.range(of: #"^<\d+;\d+;\d+[Mm]$"#, options: .regularExpression) != nil {
                return .complete
            }
            return .incomplete
        }

        return .complete
    }
}
