import Foundation

public enum PiTUITerminalImage {
    // Detects terminal image protocol escape sequences embedded anywhere in a line.
    // Used to avoid treating image payload rows as normal text during wrapping/layout.
    public static func isImageLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        // iTerm2 inline image protocol (OSC 1337 File=... BEL/ST)
        if line.contains("\u{001B}]1337;File=") {
            return true
        }
        // Kitty graphics protocol (APC ESC _G ... ST)
        if line.contains("\u{001B}_G") {
            return true
        }
        return false
    }

    public struct CellDimensions: Equatable, Sendable {
        public var widthPx: Int
        public var heightPx: Int

        public init(widthPx: Int, heightPx: Int) {
            self.widthPx = max(1, widthPx)
            self.heightPx = max(1, heightPx)
        }
    }

    public struct ImageDimensions: Equatable, Sendable {
        public var widthPx: Int
        public var heightPx: Int

        public init(widthPx: Int, heightPx: Int) {
            self.widthPx = max(1, widthPx)
            self.heightPx = max(1, heightPx)
        }
    }

    public enum ImageProtocol: String, Equatable, Sendable {
        case kitty
        case iterm2
    }

    public struct Capabilities: Equatable, Sendable {
        public var images: ImageProtocol?
        public var trueColor: Bool
        public var hyperlinks: Bool

        public init(images: ImageProtocol?, trueColor: Bool = true, hyperlinks: Bool = true) {
            self.images = images
            self.trueColor = trueColor
            self.hyperlinks = hyperlinks
        }
    }

    public static func calculateRows(
        imageDimensions: ImageDimensions,
        targetWidthCells: Int,
        cellDimensions: CellDimensions = .init(widthPx: 9, heightPx: 18)
    ) -> Int {
        let targetWidthPx = max(1, targetWidthCells) * cellDimensions.widthPx
        let scale = Double(targetWidthPx) / Double(max(1, imageDimensions.widthPx))
        let scaledHeightPx = Double(imageDimensions.heightPx) * scale
        return max(1, Int(ceil(scaledHeightPx / Double(cellDimensions.heightPx))))
    }

    public static func encodeKitty(
        base64Data: String,
        columns: Int? = nil,
        rows: Int? = nil,
        imageId: Int? = nil
    ) -> String {
        let chunkSize = 4096
        var params = ["a=T", "f=100", "q=2"]
        if let columns { params.append("c=\(columns)") }
        if let rows { params.append("r=\(rows)") }
        if let imageId { params.append("i=\(imageId)") }

        if base64Data.count <= chunkSize {
            return "\u{001B}_G\(params.joined(separator: ","));\(base64Data)\u{001B}\\"
        }

        var chunks: [String] = []
        var start = base64Data.startIndex
        var isFirst = true
        while start < base64Data.endIndex {
            let end = base64Data.index(start, offsetBy: chunkSize, limitedBy: base64Data.endIndex) ?? base64Data.endIndex
            let chunk = String(base64Data[start..<end])
            let isLast = end == base64Data.endIndex
            if isFirst {
                chunks.append("\u{001B}_G\(params.joined(separator: ",")),m=1;\(chunk)\u{001B}\\")
                isFirst = false
            } else if isLast {
                chunks.append("\u{001B}_Gm=0;\(chunk)\u{001B}\\")
            } else {
                chunks.append("\u{001B}_Gm=1;\(chunk)\u{001B}\\")
            }
            start = end
        }
        return chunks.joined()
    }

    public static func encodeITerm2(
        base64Data: String,
        width: String? = nil,
        height: String? = nil,
        filename: String? = nil,
        inline: Bool = true
    ) -> String {
        var params = ["inline=\(inline ? 1 : 0)"]
        if let width { params.append("width=\(width)") }
        if let height { params.append("height=\(height)") }
        if let filename, let nameData = filename.data(using: .utf8) {
            params.append("name=\(nameData.base64EncodedString())")
        }
        return "\u{001B}]1337;File=\(params.joined(separator: ";")):\(base64Data)\u{0007}"
    }

    public static func imageFallback(
        mimeType: String,
        dimensions: ImageDimensions,
        filename: String? = nil
    ) -> String {
        let name = filename.map { " \($0)" } ?? ""
        return "[Image\(name): \(mimeType) \(dimensions.widthPx)x\(dimensions.heightPx)]"
    }

    public static func allocateImageId() -> Int {
        Int.random(in: 1...Int(UInt32.max))
    }
}
