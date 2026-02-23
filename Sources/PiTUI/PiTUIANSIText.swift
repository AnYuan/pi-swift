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
            width += 1
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

            if width >= maxWidth {
                break
            }

            output.append(iterator.next()!)
            width += 1
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
