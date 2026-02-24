public struct PiTUIImageTheme: @unchecked Sendable {
    public var fallbackColor: (String) -> String

    public init(fallbackColor: @escaping (String) -> String) {
        self.fallbackColor = fallbackColor
    }

    public static let plain = PiTUIImageTheme(fallbackColor: { $0 })
}

public struct PiTUIImageOptions: Equatable, Sendable {
    public var maxWidthCells: Int?
    public var filename: String?
    public var imageId: Int?

    public init(maxWidthCells: Int? = nil, filename: String? = nil, imageId: Int? = nil) {
        self.maxWidthCells = maxWidthCells
        self.filename = filename
        self.imageId = imageId
    }
}

public final class PiTUIImage: PiTUIComponent {
    private let base64Data: String
    private let mimeType: String
    private let dimensions: PiTUITerminalImage.ImageDimensions
    private let theme: PiTUIImageTheme
    private let options: PiTUIImageOptions
    private let capabilitiesProvider: () -> PiTUITerminalImage.Capabilities
    private let imageIdAllocator: () -> Int

    private var cachedWidth: Int?
    private var cachedLines: [String]?
    private var imageId: Int?

    public init(
        base64Data: String,
        mimeType: String,
        dimensions: PiTUITerminalImage.ImageDimensions,
        theme: PiTUIImageTheme = .plain,
        options: PiTUIImageOptions = .init(),
        capabilitiesProvider: @escaping () -> PiTUITerminalImage.Capabilities = { .init(images: nil) },
        imageIdAllocator: @escaping () -> Int = { PiTUITerminalImage.allocateImageId() }
    ) {
        self.base64Data = base64Data
        self.mimeType = mimeType
        self.dimensions = dimensions
        self.theme = theme
        self.options = options
        self.capabilitiesProvider = capabilitiesProvider
        self.imageIdAllocator = imageIdAllocator
        self.imageId = options.imageId
    }

    public func invalidate() {
        cachedWidth = nil
        cachedLines = nil
    }

    public func getImageId() -> Int? {
        imageId
    }

    public func render(width: Int) -> [String] {
        let width = max(1, width)
        if cachedWidth == width, let cachedLines {
            return cachedLines
        }

        let maxWidthCells = max(1, min(max(1, width - 2), options.maxWidthCells ?? 60))
        let capabilities = capabilitiesProvider()
        let lines: [String]

        if let protocolType = capabilities.images {
            let rows = PiTUITerminalImage.calculateRows(imageDimensions: dimensions, targetWidthCells: maxWidthCells)
            let sequence: String
            switch protocolType {
            case .kitty:
                let currentId = imageId ?? imageIdAllocator()
                imageId = currentId
                sequence = PiTUITerminalImage.encodeKitty(
                    base64Data: base64Data,
                    columns: maxWidthCells,
                    rows: rows,
                    imageId: currentId
                )
            case .iterm2:
                sequence = PiTUITerminalImage.encodeITerm2(
                    base64Data: base64Data,
                    width: "\(maxWidthCells)ch",
                    filename: options.filename
                )
            }

            if rows <= 1 {
                lines = [sequence]
            } else {
                let moveUp = "\u{001B}[\(rows - 1)A"
                lines = Array(repeating: "", count: rows - 1) + [moveUp + sequence]
            }
        } else {
            let fallback = PiTUITerminalImage.imageFallback(
                mimeType: mimeType,
                dimensions: dimensions,
                filename: options.filename
            )
            lines = [theme.fallbackColor(fallback)]
        }

        cachedWidth = width
        cachedLines = lines
        return lines
    }
}
