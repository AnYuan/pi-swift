import Foundation

public final class PiTUIMarkdown: PiTUIComponent {
    private var source: String
    private var cacheWidth: Int?
    private var cacheLines: [String]?

    public private(set) var debugRenderPasses: Int = 0

    public init(_ source: String = "") {
        self.source = source
    }

    public func setMarkdown(_ source: String) {
        self.source = source
        invalidate()
    }

    public func invalidate() {
        cacheWidth = nil
        cacheLines = nil
    }

    public func render(width: Int) -> [String] {
        let width = max(1, width)
        if cacheWidth == width, let cacheLines {
            return cacheLines
        }

        debugRenderPasses += 1
        let lines = renderMarkdown(source, width: width)
        cacheWidth = width
        cacheLines = lines
        return lines
    }

    private func renderMarkdown(_ source: String, width: Int) -> [String] {
        var output: [String] = []
        var inFence = false

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("```") {
                inFence.toggle()
                continue
            }

            if PiTUITerminalImage.isImageLine(rawLine) {
                output.append(rawLine)
                continue
            }

            if inFence {
                output.append(contentsOf: wrap(rawLine, width: width))
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append("")
                continue
            }

            if let heading = headingText(from: rawLine) {
                output.append(contentsOf: wrap(heading.uppercased(), width: width))
                continue
            }

            if let bullet = bulletText(from: rawLine) {
                output.append(contentsOf: wrapPrefixed(bullet, prefix: "• ", width: width))
                continue
            }

            if rawLine.hasPrefix("> ") {
                output.append(contentsOf: wrapPrefixed(renderInline(String(rawLine.dropFirst(2))), prefix: "│ ", width: width))
                continue
            }

            output.append(contentsOf: wrap(renderInline(rawLine), width: width))
        }

        return output
    }

    private func headingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }
        return renderInline(remainder)
    }

    private func bulletText(from line: String) -> String? {
        let trimmedLeft = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmedLeft.hasPrefix("- ") || trimmedLeft.hasPrefix("* ") else { return nil }
        return renderInline(String(trimmedLeft.dropFirst(2)))
    }

    private func renderInline(_ line: String) -> String {
        var value = line
        value = value.replacingOccurrences(of: "**", with: "")
        value = value.replacingOccurrences(of: "__", with: "")
        value = value.replacingOccurrences(of: "`", with: "")
        value = value.replacingOccurrences(of: "*", with: "")

        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = value as NSString
            let matches = regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches where match.numberOfRanges == 3 {
                let text = ns.substring(with: match.range(at: 1))
                let url = ns.substring(with: match.range(at: 2))
                let replacement = "\(text) (\(url))"
                value = (value as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        return value
    }

    private func wrapPrefixed(_ text: String, prefix: String, width: Int) -> [String] {
        let prefixWidth = PiTUIANSIText.visibleWidth(prefix)
        let wrapped = wrap(text, width: max(1, width - prefixWidth))
        guard !wrapped.isEmpty else { return [prefix] }
        return wrapped.enumerated().map { index, line in
            (index == 0 ? prefix : String(repeating: " ", count: prefix.count)) + line
        }
    }

    private func wrap(_ text: String, width: Int) -> [String] {
        let width = max(1, width)
        guard !text.isEmpty else { return [""] }
        if PiTUIANSIText.visibleWidth(text) <= width { return [text] }

        var result: [String] = []
        var current = ""

        for word in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            if current.isEmpty {
                current = PiTUIANSIText.truncateToVisibleWidth(word, maxWidth: width)
                continue
            }

            let candidate = current + " " + word
            if PiTUIANSIText.visibleWidth(candidate) <= width {
                current = candidate
            } else {
                result.append(current)
                current = PiTUIANSIText.truncateToVisibleWidth(word, maxWidth: width)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result.isEmpty ? [""] : result
    }
}
