import Foundation

public struct PiAISSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String?, data: String, id: String?) {
        self.event = event
        self.data = data
        self.id = id
    }
}

public struct PiAISSEParser: Sendable {
    private var bufferedLine = ""
    private var currentEvent: String?
    private var currentID: String?
    private var currentDataLines: [String] = []

    public init() {}

    public mutating func feed(_ chunk: String) -> [PiAISSEEvent] {
        bufferedLine += chunk
        var events: [PiAISSEEvent] = []

        while let newlineRange = bufferedLine.range(of: "\n") {
            var line = String(bufferedLine[..<newlineRange.lowerBound])
            bufferedLine = String(bufferedLine[newlineRange.upperBound...])

            if line.hasSuffix("\r") {
                line.removeLast()
            }

            if line.isEmpty {
                if let event = flushCurrentEventIfNeeded() {
                    events.append(event)
                }
                continue
            }

            if line.hasPrefix(":") {
                continue
            }

            let field: String
            let value: String
            if let colon = line.firstIndex(of: ":") {
                field = String(line[..<colon])
                let rawValue = String(line[line.index(after: colon)...])
                value = rawValue.hasPrefix(" ") ? String(rawValue.dropFirst()) : rawValue
            } else {
                field = line
                value = ""
            }

            switch field {
            case "event":
                currentEvent = value
            case "data":
                currentDataLines.append(value)
            case "id":
                currentID = value
            default:
                continue
            }
        }

        return events
    }

    private mutating func flushCurrentEventIfNeeded() -> PiAISSEEvent? {
        guard currentEvent != nil || currentID != nil || !currentDataLines.isEmpty else {
            return nil
        }
        defer {
            currentEvent = nil
            currentID = nil
            currentDataLines.removeAll(keepingCapacity: true)
        }
        return PiAISSEEvent(
            event: currentEvent,
            data: currentDataLines.joined(separator: "\n"),
            id: currentID
        )
    }
}

