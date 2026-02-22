import Foundation

public enum PiStreamEvent: Codable, Equatable, Sendable {
    case start(modelID: String?)
    case textStart
    case textDelta(String)
    case textEnd
    case toolCall(PiToolCall)
    case toolResult(PiToolResult)
    case finish(stopReason: String?)
    case error(message: String)

    enum CodingKeys: String, CodingKey {
        case kind
        case modelID
        case delta
        case toolCall
        case toolResult
        case stopReason
        case message
    }

    enum Kind: String, Codable {
        case start
        case textStart
        case textDelta
        case textEnd
        case toolCall
        case toolResult
        case finish
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .start:
            self = .start(modelID: try container.decodeIfPresent(String.self, forKey: .modelID))
        case .textStart:
            self = .textStart
        case .textDelta:
            self = .textDelta(try container.decode(String.self, forKey: .delta))
        case .textEnd:
            self = .textEnd
        case .toolCall:
            self = .toolCall(try container.decode(PiToolCall.self, forKey: .toolCall))
        case .toolResult:
            self = .toolResult(try container.decode(PiToolResult.self, forKey: .toolResult))
        case .finish:
            self = .finish(stopReason: try container.decodeIfPresent(String.self, forKey: .stopReason))
        case .error:
            self = .error(message: try container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let modelID):
            try container.encode(Kind.start, forKey: .kind)
            try container.encodeIfPresent(modelID, forKey: .modelID)
        case .textStart:
            try container.encode(Kind.textStart, forKey: .kind)
        case .textDelta(let delta):
            try container.encode(Kind.textDelta, forKey: .kind)
            try container.encode(delta, forKey: .delta)
        case .textEnd:
            try container.encode(Kind.textEnd, forKey: .kind)
        case .toolCall(let toolCall):
            try container.encode(Kind.toolCall, forKey: .kind)
            try container.encode(toolCall, forKey: .toolCall)
        case .toolResult(let toolResult):
            try container.encode(Kind.toolResult, forKey: .kind)
            try container.encode(toolResult, forKey: .toolResult)
        case .finish(let stopReason):
            try container.encode(Kind.finish, forKey: .kind)
            try container.encodeIfPresent(stopReason, forKey: .stopReason)
        case .error(let message):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

