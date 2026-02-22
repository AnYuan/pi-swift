import Foundation

public enum PiMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case toolResult
}

public struct PiAttachmentReference: Codable, Equatable, Sendable {
    public var id: String
    public var mimeType: String
    public var name: String?

    public init(id: String, mimeType: String, name: String? = nil) {
        self.id = id
        self.mimeType = mimeType
        self.name = name
    }
}

public enum PiMessagePart: Codable, Equatable, Sendable {
    case text(String)
    case image(PiAttachmentReference)
    case toolCall(PiToolCall)
    case toolResult(PiToolResult)

    enum CodingKeys: String, CodingKey {
        case kind
        case text
        case image
        case toolCall
        case toolResult
    }

    enum Kind: String, Codable {
        case text
        case image
        case toolCall
        case toolResult
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(PiAttachmentReference.self, forKey: .image))
        case .toolCall:
            self = .toolCall(try container.decode(PiToolCall.self, forKey: .toolCall))
        case .toolResult:
            self = .toolResult(try container.decode(PiToolResult.self, forKey: .toolResult))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .image(let value):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(value, forKey: .image)
        case .toolCall(let value):
            try container.encode(Kind.toolCall, forKey: .kind)
            try container.encode(value, forKey: .toolCall)
        case .toolResult(let value):
            try container.encode(Kind.toolResult, forKey: .kind)
            try container.encode(value, forKey: .toolResult)
        }
    }
}

public struct PiMessage: Codable, Equatable, Sendable {
    public var id: String
    public var role: PiMessageRole
    public var parts: [PiMessagePart]

    public init(id: String, role: PiMessageRole, parts: [PiMessagePart]) {
        self.id = id
        self.role = role
        self.parts = parts
    }
}

