public struct PiTUIRenderEdit: Equatable, Sendable {
    public var row: Int
    public var content: String

    public init(row: Int, content: String) {
        self.row = row
        self.content = content
    }
}

public enum PiTUIRenderPlan: Equatable, Sendable {
    case none
    case fullRedraw(clearScreen: Bool, lines: [String])
    case differential(edits: [PiTUIRenderEdit], clearedRows: [Int])
}

public struct PiTUIRenderStep: Equatable, Sendable {
    public var plan: PiTUIRenderPlan
    public var isFullRedraw: Bool

    public init(plan: PiTUIRenderPlan, isFullRedraw: Bool) {
        self.plan = plan
        self.isFullRedraw = isFullRedraw
    }
}

public struct PiTUIRenderBuffer: Sendable {
    public private(set) var previousLines: [String] = []
    public private(set) var previousWidth: Int = 0
    public private(set) var maxLinesRendered: Int = 0

    public init() {}

    public mutating func reset() {
        previousLines = []
        previousWidth = 0
        maxLinesRendered = 0
    }

    public mutating func makeStep(
        width: Int,
        newLines rawLines: [String],
        clearOnShrink: Bool
    ) -> PiTUIRenderStep {
        let clampedWidth = max(1, width)
        let newLines = rawLines.map { String($0.prefix(clampedWidth)) }
        let widthChanged = previousWidth != 0 && previousWidth != clampedWidth

        if previousLines.isEmpty && !widthChanged {
            previousLines = newLines
            previousWidth = clampedWidth
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            return .init(plan: .fullRedraw(clearScreen: false, lines: newLines), isFullRedraw: true)
        }

        if widthChanged {
            previousLines = newLines
            previousWidth = clampedWidth
            maxLinesRendered = newLines.count
            return .init(plan: .fullRedraw(clearScreen: true, lines: newLines), isFullRedraw: true)
        }

        if clearOnShrink && newLines.count < maxLinesRendered {
            previousLines = newLines
            previousWidth = clampedWidth
            maxLinesRendered = newLines.count
            return .init(plan: .fullRedraw(clearScreen: true, lines: newLines), isFullRedraw: true)
        }

        let commonCount = min(previousLines.count, newLines.count)
        var edits: [PiTUIRenderEdit] = []
        edits.reserveCapacity(max(previousLines.count, newLines.count))

        for row in 0..<commonCount where previousLines[row] != newLines[row] {
            edits.append(.init(row: row, content: newLines[row]))
        }

        if newLines.count > previousLines.count {
            for row in previousLines.count..<newLines.count {
                edits.append(.init(row: row, content: newLines[row]))
            }
        }

        let clearedRows: [Int]
        if previousLines.count > newLines.count {
            clearedRows = Array(newLines.count..<previousLines.count)
        } else {
            clearedRows = []
        }

        previousLines = newLines
        previousWidth = clampedWidth
        maxLinesRendered = max(maxLinesRendered, newLines.count)

        if edits.isEmpty && clearedRows.isEmpty {
            return .init(plan: .none, isFullRedraw: false)
        }

        return .init(plan: .differential(edits: edits, clearedRows: clearedRows), isFullRedraw: false)
    }
}
