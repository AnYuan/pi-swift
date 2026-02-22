import Foundation
import PiCoreTypes

public typealias PiAIApi = String
public typealias PiAIProvider = String
public typealias PiAITool = PiToolDefinition

public struct PiAITextContent: Codable, Equatable, Sendable {
    public var text: String
    public var textSignature: String?

    public init(text: String, textSignature: String? = nil) {
        self.text = text
        self.textSignature = textSignature
    }
}

public struct PiAIThinkingContent: Codable, Equatable, Sendable {
    public var thinking: String
    public var thinkingSignature: String?

    public init(thinking: String, thinkingSignature: String? = nil) {
        self.thinking = thinking
        self.thinkingSignature = thinkingSignature
    }
}

public struct PiAIImageContent: Codable, Equatable, Sendable {
    public var data: String
    public var mimeType: String

    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct PiAIToolCallContent: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]
    public var thoughtSignature: String?

    public init(id: String, name: String, arguments: [String: JSONValue], thoughtSignature: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.thoughtSignature = thoughtSignature
    }
}

public enum PiAIUserContentPart: Codable, Equatable, Sendable {
    case text(PiAITextContent)
    case image(PiAIImageContent)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case image
    }

    enum Kind: String, Codable {
        case text
        case image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(PiAITextContent.self, forKey: .text))
        case .image:
            self = .image(try container.decode(PiAIImageContent.self, forKey: .image))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let value):
            try container.encode(Kind.image, forKey: .type)
            try container.encode(value, forKey: .image)
        }
    }
}

public typealias PiAIToolResultContentPart = PiAIUserContentPart

public enum PiAIUserContent: Codable, Equatable, Sendable {
    case text(String)
    case parts([PiAIUserContentPart])

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let text = try? single.decode(String.self) {
            self = .text(text)
            return
        }
        if let parts = try? single.decode([PiAIUserContentPart].self) {
            self = .parts(parts)
            return
        }
        throw DecodingError.dataCorruptedError(in: single, debugDescription: "Expected string or [PiAIUserContentPart]")
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try single.encode(value)
        case .parts(let parts):
            try single.encode(parts)
        }
    }
}

public enum PiAIAssistantContentPart: Codable, Equatable, Sendable {
    case text(PiAITextContent)
    case thinking(PiAIThinkingContent)
    case toolCall(PiAIToolCallContent)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case thinking
        case toolCall
    }

    enum Kind: String, Codable {
        case text
        case thinking
        case toolCall
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(PiAITextContent.self, forKey: .text))
        case .thinking:
            self = .thinking(try container.decode(PiAIThinkingContent.self, forKey: .thinking))
        case .toolCall:
            self = .toolCall(try container.decode(PiAIToolCallContent.self, forKey: .toolCall))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .thinking(let value):
            try container.encode(Kind.thinking, forKey: .type)
            try container.encode(value, forKey: .thinking)
        case .toolCall(let value):
            try container.encode(Kind.toolCall, forKey: .type)
            try container.encode(value, forKey: .toolCall)
        }
    }
}

public struct PiAIUsageCost: Codable, Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    public var total: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double, total: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.total = total
    }

    public static let zero = PiAIUsageCost(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0)
}

public struct PiAIUsage: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var totalTokens: Int
    public var cost: PiAIUsageCost

    public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int, totalTokens: Int, cost: PiAIUsageCost) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.totalTokens = totalTokens
        self.cost = cost
    }

    public static let zero = PiAIUsage(
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
        totalTokens: 0,
        cost: .zero
    )
}

public enum PiAIStopReason: String, Codable, Equatable, Sendable {
    case stop
    case length
    case toolUse
    case error
    case aborted
}

public struct PiAIUserMessage: Codable, Equatable, Sendable {
    public var content: PiAIUserContent
    public var timestamp: Int64

    public init(content: PiAIUserContent, timestamp: Int64) {
        self.content = content
        self.timestamp = timestamp
    }
}

public struct PiAIAssistantMessage: Codable, Equatable, Sendable {
    public var content: [PiAIAssistantContentPart]
    public var api: PiAIApi
    public var provider: PiAIProvider
    public var model: String
    public var usage: PiAIUsage
    public var stopReason: PiAIStopReason
    public var errorMessage: String?
    public var timestamp: Int64

    public init(
        content: [PiAIAssistantContentPart],
        api: PiAIApi,
        provider: PiAIProvider,
        model: String,
        usage: PiAIUsage,
        stopReason: PiAIStopReason,
        errorMessage: String? = nil,
        timestamp: Int64
    ) {
        self.content = content
        self.api = api
        self.provider = provider
        self.model = model
        self.usage = usage
        self.stopReason = stopReason
        self.errorMessage = errorMessage
        self.timestamp = timestamp
    }
}

public struct PiAIToolResultMessage: Codable, Equatable, Sendable {
    public var toolCallId: String
    public var toolName: String
    public var content: [PiAIToolResultContentPart]
    public var details: JSONValue?
    public var isError: Bool
    public var timestamp: Int64

    public init(
        toolCallId: String,
        toolName: String,
        content: [PiAIToolResultContentPart],
        details: JSONValue? = nil,
        isError: Bool,
        timestamp: Int64
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.content = content
        self.details = details
        self.isError = isError
        self.timestamp = timestamp
    }
}

public enum PiAIMessage: Codable, Equatable, Sendable {
    case user(PiAIUserMessage)
    case assistant(PiAIAssistantMessage)
    case toolResult(PiAIToolResultMessage)

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case timestamp
        case api
        case provider
        case model
        case usage
        case stopReason
        case errorMessage
        case toolCallId
        case toolName
        case details
        case isError
    }

    enum Role: String, Codable {
        case user
        case assistant
        case toolResult
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(Role.self, forKey: .role)
        switch role {
        case .user:
            self = .user(.init(
                content: try container.decode(PiAIUserContent.self, forKey: .content),
                timestamp: try container.decode(Int64.self, forKey: .timestamp)
            ))
        case .assistant:
            self = .assistant(.init(
                content: try container.decode([PiAIAssistantContentPart].self, forKey: .content),
                api: try container.decode(String.self, forKey: .api),
                provider: try container.decode(String.self, forKey: .provider),
                model: try container.decode(String.self, forKey: .model),
                usage: try container.decode(PiAIUsage.self, forKey: .usage),
                stopReason: try container.decode(PiAIStopReason.self, forKey: .stopReason),
                errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage),
                timestamp: try container.decode(Int64.self, forKey: .timestamp)
            ))
        case .toolResult:
            self = .toolResult(.init(
                toolCallId: try container.decode(String.self, forKey: .toolCallId),
                toolName: try container.decode(String.self, forKey: .toolName),
                content: try container.decode([PiAIToolResultContentPart].self, forKey: .content),
                details: try container.decodeIfPresent(JSONValue.self, forKey: .details),
                isError: try container.decode(Bool.self, forKey: .isError),
                timestamp: try container.decode(Int64.self, forKey: .timestamp)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let message):
            try container.encode(Role.user, forKey: .role)
            try container.encode(message.content, forKey: .content)
            try container.encode(message.timestamp, forKey: .timestamp)
        case .assistant(let message):
            try container.encode(Role.assistant, forKey: .role)
            try container.encode(message.content, forKey: .content)
            try container.encode(message.api, forKey: .api)
            try container.encode(message.provider, forKey: .provider)
            try container.encode(message.model, forKey: .model)
            try container.encode(message.usage, forKey: .usage)
            try container.encode(message.stopReason, forKey: .stopReason)
            try container.encodeIfPresent(message.errorMessage, forKey: .errorMessage)
            try container.encode(message.timestamp, forKey: .timestamp)
        case .toolResult(let message):
            try container.encode(Role.toolResult, forKey: .role)
            try container.encode(message.toolCallId, forKey: .toolCallId)
            try container.encode(message.toolName, forKey: .toolName)
            try container.encode(message.content, forKey: .content)
            try container.encodeIfPresent(message.details, forKey: .details)
            try container.encode(message.isError, forKey: .isError)
            try container.encode(message.timestamp, forKey: .timestamp)
        }
    }
}

public struct PiAIContext: Codable, Equatable, Sendable {
    public var systemPrompt: String?
    public var messages: [PiAIMessage]
    public var tools: [PiAITool]?

    public init(systemPrompt: String? = nil, messages: [PiAIMessage], tools: [PiAITool]? = nil) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
    }
}

public enum PiAIAssistantMessageEvent: Codable, Equatable, Sendable {
    case start(partial: PiAIAssistantMessage)
    case textStart(contentIndex: Int, partial: PiAIAssistantMessage)
    case textDelta(contentIndex: Int, delta: String, partial: PiAIAssistantMessage)
    case textEnd(contentIndex: Int, content: String, partial: PiAIAssistantMessage)
    case thinkingStart(contentIndex: Int, partial: PiAIAssistantMessage)
    case thinkingDelta(contentIndex: Int, delta: String, partial: PiAIAssistantMessage)
    case thinkingEnd(contentIndex: Int, content: String, partial: PiAIAssistantMessage)
    case toolCallStart(contentIndex: Int, partial: PiAIAssistantMessage)
    case toolCallDelta(contentIndex: Int, delta: String, partial: PiAIAssistantMessage)
    case toolCallEnd(contentIndex: Int, toolCall: PiAIToolCallContent, partial: PiAIAssistantMessage)
    case done(reason: PiAIStopReason, message: PiAIAssistantMessage)
    case error(reason: PiAIStopReason, error: PiAIAssistantMessage)

    enum CodingKeys: String, CodingKey {
        case type
        case contentIndex
        case delta
        case content
        case partial
        case toolCall
        case reason
        case message
        case error
    }

    enum EventType: String, Codable {
        case start
        case textStart = "text_start"
        case textDelta = "text_delta"
        case textEnd = "text_end"
        case thinkingStart = "thinking_start"
        case thinkingDelta = "thinking_delta"
        case thinkingEnd = "thinking_end"
        case toolCallStart = "toolcall_start"
        case toolCallDelta = "toolcall_delta"
        case toolCallEnd = "toolcall_end"
        case done
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .start:
            self = .start(partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial))
        case .textStart:
            self = .textStart(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .textDelta:
            self = .textDelta(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                delta: try container.decode(String.self, forKey: .delta),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .textEnd:
            self = .textEnd(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                content: try container.decode(String.self, forKey: .content),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .thinkingStart:
            self = .thinkingStart(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .thinkingDelta:
            self = .thinkingDelta(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                delta: try container.decode(String.self, forKey: .delta),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .thinkingEnd:
            self = .thinkingEnd(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                content: try container.decode(String.self, forKey: .content),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .toolCallStart:
            self = .toolCallStart(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .toolCallDelta:
            self = .toolCallDelta(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                delta: try container.decode(String.self, forKey: .delta),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .toolCallEnd:
            self = .toolCallEnd(
                contentIndex: try container.decode(Int.self, forKey: .contentIndex),
                toolCall: try container.decode(PiAIToolCallContent.self, forKey: .toolCall),
                partial: try container.decode(PiAIAssistantMessage.self, forKey: .partial)
            )
        case .done:
            self = .done(
                reason: try container.decode(PiAIStopReason.self, forKey: .reason),
                message: try container.decode(PiAIAssistantMessage.self, forKey: .message)
            )
        case .error:
            self = .error(
                reason: try container.decode(PiAIStopReason.self, forKey: .reason),
                error: try container.decode(PiAIAssistantMessage.self, forKey: .error)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start(let partial):
            try container.encode(EventType.start, forKey: .type)
            try container.encode(partial, forKey: .partial)
        case .textStart(let contentIndex, let partial):
            try container.encode(EventType.textStart, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(partial, forKey: .partial)
        case .textDelta(let contentIndex, let delta, let partial):
            try container.encode(EventType.textDelta, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(delta, forKey: .delta)
            try container.encode(partial, forKey: .partial)
        case .textEnd(let contentIndex, let content, let partial):
            try container.encode(EventType.textEnd, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(content, forKey: .content)
            try container.encode(partial, forKey: .partial)
        case .thinkingStart(let contentIndex, let partial):
            try container.encode(EventType.thinkingStart, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(partial, forKey: .partial)
        case .thinkingDelta(let contentIndex, let delta, let partial):
            try container.encode(EventType.thinkingDelta, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(delta, forKey: .delta)
            try container.encode(partial, forKey: .partial)
        case .thinkingEnd(let contentIndex, let content, let partial):
            try container.encode(EventType.thinkingEnd, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(content, forKey: .content)
            try container.encode(partial, forKey: .partial)
        case .toolCallStart(let contentIndex, let partial):
            try container.encode(EventType.toolCallStart, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(partial, forKey: .partial)
        case .toolCallDelta(let contentIndex, let delta, let partial):
            try container.encode(EventType.toolCallDelta, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(delta, forKey: .delta)
            try container.encode(partial, forKey: .partial)
        case .toolCallEnd(let contentIndex, let toolCall, let partial):
            try container.encode(EventType.toolCallEnd, forKey: .type)
            try container.encode(contentIndex, forKey: .contentIndex)
            try container.encode(toolCall, forKey: .toolCall)
            try container.encode(partial, forKey: .partial)
        case .done(let reason, let message):
            try container.encode(EventType.done, forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(message, forKey: .message)
        case .error(let reason, let error):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(reason, forKey: .reason)
            try container.encode(error, forKey: .error)
        }
    }
}

