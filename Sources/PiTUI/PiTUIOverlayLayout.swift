import Foundation

public typealias PiTUISizeValue = IntOrPercent

public enum IntOrPercent: Equatable, Sendable {
    case absolute(Int)
    case percent(Double)

    public static func percent(_ value: Int) -> IntOrPercent {
        .percent(Double(value))
    }
}

public enum PiTUIOverlayAnchor: String, CaseIterable, Sendable {
    case topLeft = "top-left"
    case topCenter = "top-center"
    case topRight = "top-right"
    case leftCenter = "left-center"
    case center
    case rightCenter = "right-center"
    case bottomLeft = "bottom-left"
    case bottomCenter = "bottom-center"
    case bottomRight = "bottom-right"
}

public struct PiTUIOverlayMargin: Equatable, Sendable {
    public var top: Int?
    public var right: Int?
    public var bottom: Int?
    public var left: Int?

    public init(top: Int? = nil, right: Int? = nil, bottom: Int? = nil, left: Int? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }
}

public enum PiTUIOverlayMarginValue: Equatable, Sendable {
    case uniform(Int)
    case edges(PiTUIOverlayMargin)
}

public struct PiTUIOverlayOptions: Equatable, Sendable {
    public var width: PiTUISizeValue?
    public var minWidth: Int?
    public var maxHeight: PiTUISizeValue?

    public var anchor: PiTUIOverlayAnchor?
    public var offsetX: Int?
    public var offsetY: Int?

    public var row: PiTUISizeValue?
    public var col: PiTUISizeValue?

    public var margin: PiTUIOverlayMarginValue?

    public init(
        width: PiTUISizeValue? = nil,
        minWidth: Int? = nil,
        maxHeight: PiTUISizeValue? = nil,
        anchor: PiTUIOverlayAnchor? = nil,
        offsetX: Int? = nil,
        offsetY: Int? = nil,
        row: PiTUISizeValue? = nil,
        col: PiTUISizeValue? = nil,
        margin: PiTUIOverlayMarginValue? = nil
    ) {
        self.width = width
        self.minWidth = minWidth
        self.maxHeight = maxHeight
        self.anchor = anchor
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.row = row
        self.col = col
        self.margin = margin
    }
}

public struct PiTUIOverlayResolvedLayout: Equatable, Sendable {
    public var width: Int
    public var row: Int
    public var col: Int
    public var maxHeight: Int?
}

public enum PiTUIOverlayLayoutPlanner {
    public static func resolve(
        options: PiTUIOverlayOptions?,
        overlayHeight: Int,
        termWidth: Int,
        termHeight: Int
    ) -> PiTUIOverlayResolvedLayout {
        let opt = options ?? .init()

        let margin = resolvedMargin(opt.margin)
        let marginTop = max(0, margin.top ?? 0)
        let marginRight = max(0, margin.right ?? 0)
        let marginBottom = max(0, margin.bottom ?? 0)
        let marginLeft = max(0, margin.left ?? 0)

        let availWidth = max(1, termWidth - marginLeft - marginRight)
        let availHeight = max(1, termHeight - marginTop - marginBottom)

        var width = parseSizeValue(opt.width, reference: termWidth) ?? min(80, availWidth)
        if let minWidth = opt.minWidth { width = max(width, minWidth) }
        width = max(1, min(width, availWidth))

        var maxHeight = parseSizeValue(opt.maxHeight, reference: termHeight)
        if let value = maxHeight { maxHeight = max(1, min(value, availHeight)) }

        let effectiveHeight = maxHeight.map { min(overlayHeight, $0) } ?? overlayHeight

        var row: Int
        var col: Int

        if let rowValue = opt.row {
            row = resolvePosition(
                rowValue,
                referenceSize: termHeight,
                availableSize: availHeight,
                contentSize: effectiveHeight,
                marginStart: marginTop
            ) ?? resolveAnchorRow(opt.anchor ?? .center, height: effectiveHeight, availHeight: availHeight, marginTop: marginTop)
        } else {
            row = resolveAnchorRow(opt.anchor ?? .center, height: effectiveHeight, availHeight: availHeight, marginTop: marginTop)
        }

        if let colValue = opt.col {
            col = resolvePosition(
                colValue,
                referenceSize: termWidth,
                availableSize: availWidth,
                contentSize: width,
                marginStart: marginLeft
            ) ?? resolveAnchorCol(opt.anchor ?? .center, width: width, availWidth: availWidth, marginLeft: marginLeft)
        } else {
            col = resolveAnchorCol(opt.anchor ?? .center, width: width, availWidth: availWidth, marginLeft: marginLeft)
        }

        if let offsetY = opt.offsetY { row += offsetY }
        if let offsetX = opt.offsetX { col += offsetX }

        row = max(marginTop, min(row, termHeight - marginBottom - effectiveHeight))
        col = max(marginLeft, min(col, termWidth - marginRight - width))

        return .init(width: width, row: row, col: col, maxHeight: maxHeight)
    }

    private static func resolvedMargin(_ value: PiTUIOverlayMarginValue?) -> PiTUIOverlayMargin {
        switch value {
        case .none:
            return .init()
        case .uniform(let m):
            return .init(top: m, right: m, bottom: m, left: m)
        case .edges(let e):
            return e
        }
    }

    private static func parseSizeValue(_ value: PiTUISizeValue?, reference: Int) -> Int? {
        guard let value else { return nil }
        switch value {
        case .absolute(let n):
            return n
        case .percent(let p):
            return Int(floor((Double(reference) * p) / 100.0))
        }
    }

    private static func resolvePosition(
        _ value: PiTUISizeValue,
        referenceSize: Int,
        availableSize: Int,
        contentSize: Int,
        marginStart: Int
    ) -> Int? {
        switch value {
        case .absolute(let n):
            return n
        case .percent(let p):
            let maxPos = max(0, availableSize - contentSize)
            return marginStart + Int(floor(Double(maxPos) * (p / 100.0)))
        }
    }

    private static func resolveAnchorRow(_ anchor: PiTUIOverlayAnchor, height: Int, availHeight: Int, marginTop: Int) -> Int {
        switch anchor {
        case .topLeft, .topCenter, .topRight:
            return marginTop
        case .bottomLeft, .bottomCenter, .bottomRight:
            return marginTop + availHeight - height
        case .leftCenter, .center, .rightCenter:
            return marginTop + (availHeight - height) / 2
        }
    }

    private static func resolveAnchorCol(_ anchor: PiTUIOverlayAnchor, width: Int, availWidth: Int, marginLeft: Int) -> Int {
        switch anchor {
        case .topLeft, .leftCenter, .bottomLeft:
            return marginLeft
        case .topRight, .rightCenter, .bottomRight:
            return marginLeft + availWidth - width
        case .topCenter, .center, .bottomCenter:
            return marginLeft + (availWidth - width) / 2
        }
    }
}
