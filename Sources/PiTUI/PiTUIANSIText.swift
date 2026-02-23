public enum PiTUIANSIText {
    public static let escape = "\u{001B}"
    public static let reset = "\u{001B}[0m"

    public static func visibleWidth(_ value: String) -> Int {
        var width = 0
        var iterator = ScalarIterator(value)

        while let scalar = iterator.peek() {
            if scalar == "\u{001B}" {
                consumeEscapeSequence(&iterator)
                continue
            }
            _ = iterator.next()
            if scalar.properties.isWhitespace && scalar == "\n" {
                continue
            }
            if scalar.value < 0x20 || scalar.value == 0x7F {
                continue
            }
            width += displayWidth(of: scalar)
        }

        return width
    }

    public static func truncateToVisibleWidth(_ value: String, maxWidth: Int) -> String {
        guard maxWidth >= 0 else { return "" }
        var width = 0
        var iterator = ScalarIterator(value)
        var output = String.UnicodeScalarView()

        while let scalar = iterator.peek() {
            if scalar == "\u{001B}" {
                appendEscapeSequence(from: &iterator, to: &output)
                continue
            }

            if scalar.value < 0x20 || scalar.value == 0x7F {
                output.append(iterator.next()!)
                continue
            }

            let scalarWidth = displayWidth(of: scalar)
            if width + scalarWidth > maxWidth {
                break
            }

            output.append(iterator.next()!)
            width += scalarWidth
        }

        return String(output)
    }

    public static func ensureLineReset(_ value: String) -> String {
        guard value.contains(escape) else {
            return value
        }
        guard !value.hasSuffix(reset) else {
            return value
        }
        return value + reset
    }

    public static func sanitizeLine(_ value: String, columns: Int) -> String {
        let truncated = truncateToVisibleWidth(value, maxWidth: max(0, columns))
        return ensureLineReset(truncated)
    }

    private static func displayWidth(of scalar: UnicodeScalar) -> Int {
        if isZeroWidthScalar(scalar) {
            return 0
        }
        if isWideScalar(scalar) {
            return 2
        }
        return 1
    }

    private static func isZeroWidthScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return true
        default:
            break
        }

        switch scalar.value {
        case 0x200D, // ZWJ
            0xFE00...0xFE0F, // variation selectors
            0xE0100...0xE01EF: // variation selectors supplement
            return true
        default:
            return false
        }
    }

    private static func isWideScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
            0x2329...0x232A,
            0x2E80...0xA4CF,
            0xAC00...0xD7A3,
            0xF900...0xFAFF,
            0xFE10...0xFE19,
            0xFE30...0xFE6F,
            0xFF00...0xFF60,
            0xFFE0...0xFFE6,
            0x1F300...0x1FAFF,
            0x20000...0x2FFFD,
            0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

private struct ScalarIterator {
    private let scalars: [UnicodeScalar]
    private var index: Int = 0

    init(_ value: String) {
        self.scalars = Array(value.unicodeScalars)
    }

    mutating func peek() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    mutating func next() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        let scalar = scalars[index]
        index += 1
        return scalar
    }
}

private func consumeEscapeSequence(_ iterator: inout ScalarIterator) {
    _ = iterator.next() // ESC
    guard let next = iterator.peek() else { return }

    if next == "[" {
        _ = iterator.next()
        while let scalar = iterator.next() {
            if (0x40...0x7E).contains(scalar.value) {
                break
            }
        }
        return
    }

    if next == "]" {
        _ = iterator.next()
        while let scalar = iterator.next() {
            if scalar == "\u{0007}" {
                break
            }
            if scalar == "\u{001B}", iterator.peek() == "\\" {
                _ = iterator.next()
                break
            }
        }
        return
    }

    _ = iterator.next()
}

private func appendEscapeSequence(from iterator: inout ScalarIterator, to output: inout String.UnicodeScalarView) {
    guard let esc = iterator.next() else { return }
    output.append(esc)
    guard let next = iterator.peek() else { return }

    if next == "[" {
        output.append(iterator.next()!)
        while let scalar = iterator.next() {
            output.append(scalar)
            if (0x40...0x7E).contains(scalar.value) {
                break
            }
        }
        return
    }

    if next == "]" {
        output.append(iterator.next()!)
        while let scalar = iterator.next() {
            output.append(scalar)
            if scalar == "\u{0007}" {
                break
            }
            if scalar == "\u{001B}", iterator.peek() == "\\" {
                output.append(iterator.next()!)
                break
            }
        }
        return
    }

    output.append(iterator.next()!)
}
