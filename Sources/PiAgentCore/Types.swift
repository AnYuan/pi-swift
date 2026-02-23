import Foundation
import PiAI
import PiCoreTypes

public enum PiAgentThinkingLevel: String, Codable, Equatable, Sendable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public struct PiAgentCustomMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: JSONValue
    public var timestamp: Int64

    public init(role: String, content: JSONValue, timestamp: Int64) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum PiAgentMessage: Codable, Equatable, Sendable {
    case user(PiAIUserMessage)
    case assistant(PiAIAssistantMessage)
    case toolResult(PiAIToolResultMessage)
    case custom(PiAgentCustomMessage)

    enum CodingKeys: String, CodingKey {
        case role
        case customRole
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
        case custom
    }

    public var role: String {
        switch self {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .toolResult:
            return "toolResult"
        case .custom(let custom):
            return custom.role
        }
    }

    public var timestamp: Int64 {
        switch self {
        case .user(let message):
            return message.timestamp
        case .assistant(let message):
            return message.timestamp
        case .toolResult(let message):
            return message.timestamp
        case .custom(let message):
            return message.timestamp
        }
    }

    public var asAIMessage: PiAIMessage? {
        switch self {
        case .user(let value):
            return .user(value)
        case .assistant(let value):
            return .assistant(value)
        case .toolResult(let value):
            return .toolResult(value)
        case .custom:
            return nil
        }
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
        case .custom:
            self = .custom(.init(
                role: try container.decode(String.self, forKey: .customRole),
                content: try container.decode(JSONValue.self, forKey: .content),
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
        case .custom(let message):
            try container.encode(Role.custom, forKey: .role)
            try container.encode(message.role, forKey: .customRole)
            try container.encode(message.content, forKey: .content)
            try container.encode(message.timestamp, forKey: .timestamp)
        }
    }
}

public struct PiAgentToolExecutionResult: Codable, Equatable, Sendable {
    public var content: [PiAIToolResultContentPart]
    public var details: JSONValue

    public init(content: [PiAIToolResultContentPart], details: JSONValue) {
        self.content = content
        self.details = details
    }
}

public struct PiAgentTool: Codable, Equatable, Sendable {
    public var name: String
    public var label: String
    public var description: String
    public var parameters: PiToolParameterSchema

    public init(name: String, label: String, description: String, parameters: PiToolParameterSchema) {
        self.name = name
        self.label = label
        self.description = description
        self.parameters = parameters
    }

    public var asAITool: PiAITool {
        .init(name: name, description: description, parameters: parameters)
    }
}

public struct PiAgentContext: Codable, Equatable, Sendable {
    public var systemPrompt: String
    public var messages: [PiAgentMessage]
    public var tools: [PiAgentTool]?

    public init(systemPrompt: String, messages: [PiAgentMessage], tools: [PiAgentTool]? = nil) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
    }
}

public struct PiAgentState: Codable, Equatable, Sendable {
    public var systemPrompt: String
    public var model: PiAIModel
    public var thinkingLevel: PiAgentThinkingLevel
    public var tools: [PiAgentTool]
    public var messages: [PiAgentMessage]
    public var isStreaming: Bool
    public var streamMessage: PiAgentMessage?
    public var pendingToolCalls: Set<String>
    public var error: String?

    public init(
        systemPrompt: String,
        model: PiAIModel,
        thinkingLevel: PiAgentThinkingLevel,
        tools: [PiAgentTool],
        messages: [PiAgentMessage],
        isStreaming: Bool,
        streamMessage: PiAgentMessage?,
        pendingToolCalls: Set<String>,
        error: String? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.tools = tools
        self.messages = messages
        self.isStreaming = isStreaming
        self.streamMessage = streamMessage
        self.pendingToolCalls = pendingToolCalls
        self.error = error
    }

    public static func empty(
        model: PiAIModel,
        systemPrompt: String = "",
        thinkingLevel: PiAgentThinkingLevel = .off
    ) -> PiAgentState {
        .init(
            systemPrompt: systemPrompt,
            model: model,
            thinkingLevel: thinkingLevel,
            tools: [],
            messages: [],
            isStreaming: false,
            streamMessage: nil,
            pendingToolCalls: [],
            error: nil
        )
    }
}

public enum PiAgentEvent: Codable, Equatable, Sendable {
    case agentStart
    case agentEnd(messages: [PiAgentMessage])
    case turnStart
    case turnEnd(message: PiAgentMessage, toolResults: [PiAIToolResultMessage])
    case messageStart(message: PiAgentMessage)
    case messageUpdate(message: PiAgentMessage, assistantMessageEvent: PiAIAssistantMessageEvent)
    case messageEnd(message: PiAgentMessage)
    case toolExecutionStart(toolCallID: String, toolName: String, args: JSONValue)
    case toolExecutionUpdate(toolCallID: String, toolName: String, args: JSONValue, partialResult: PiAgentToolExecutionResult)
    case toolExecutionEnd(toolCallID: String, toolName: String, result: PiAgentToolExecutionResult, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type
        case messages
        case message
        case toolResults
        case assistantMessageEvent
        case toolCallID = "toolCallId"
        case toolName
        case args
        case partialResult
        case result
        case isError
    }

    enum EventType: String, Codable {
        case agentStart = "agent_start"
        case agentEnd = "agent_end"
        case turnStart = "turn_start"
        case turnEnd = "turn_end"
        case messageStart = "message_start"
        case messageUpdate = "message_update"
        case messageEnd = "message_end"
        case toolExecutionStart = "tool_execution_start"
        case toolExecutionUpdate = "tool_execution_update"
        case toolExecutionEnd = "tool_execution_end"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .agentStart:
            self = .agentStart
        case .agentEnd:
            self = .agentEnd(messages: try container.decode([PiAgentMessage].self, forKey: .messages))
        case .turnStart:
            self = .turnStart
        case .turnEnd:
            self = .turnEnd(
                message: try container.decode(PiAgentMessage.self, forKey: .message),
                toolResults: try container.decode([PiAIToolResultMessage].self, forKey: .toolResults)
            )
        case .messageStart:
            self = .messageStart(message: try container.decode(PiAgentMessage.self, forKey: .message))
        case .messageUpdate:
            self = .messageUpdate(
                message: try container.decode(PiAgentMessage.self, forKey: .message),
                assistantMessageEvent: try container.decode(PiAIAssistantMessageEvent.self, forKey: .assistantMessageEvent)
            )
        case .messageEnd:
            self = .messageEnd(message: try container.decode(PiAgentMessage.self, forKey: .message))
        case .toolExecutionStart:
            self = .toolExecutionStart(
                toolCallID: try container.decode(String.self, forKey: .toolCallID),
                toolName: try container.decode(String.self, forKey: .toolName),
                args: try container.decode(JSONValue.self, forKey: .args)
            )
        case .toolExecutionUpdate:
            self = .toolExecutionUpdate(
                toolCallID: try container.decode(String.self, forKey: .toolCallID),
                toolName: try container.decode(String.self, forKey: .toolName),
                args: try container.decode(JSONValue.self, forKey: .args),
                partialResult: try container.decode(PiAgentToolExecutionResult.self, forKey: .partialResult)
            )
        case .toolExecutionEnd:
            self = .toolExecutionEnd(
                toolCallID: try container.decode(String.self, forKey: .toolCallID),
                toolName: try container.decode(String.self, forKey: .toolName),
                result: try container.decode(PiAgentToolExecutionResult.self, forKey: .result),
                isError: try container.decode(Bool.self, forKey: .isError)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .agentStart:
            try container.encode(EventType.agentStart, forKey: .type)
        case .agentEnd(let messages):
            try container.encode(EventType.agentEnd, forKey: .type)
            try container.encode(messages, forKey: .messages)
        case .turnStart:
            try container.encode(EventType.turnStart, forKey: .type)
        case .turnEnd(let message, let toolResults):
            try container.encode(EventType.turnEnd, forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encode(toolResults, forKey: .toolResults)
        case .messageStart(let message):
            try container.encode(EventType.messageStart, forKey: .type)
            try container.encode(message, forKey: .message)
        case .messageUpdate(let message, let assistantMessageEvent):
            try container.encode(EventType.messageUpdate, forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encode(assistantMessageEvent, forKey: .assistantMessageEvent)
        case .messageEnd(let message):
            try container.encode(EventType.messageEnd, forKey: .type)
            try container.encode(message, forKey: .message)
        case .toolExecutionStart(let toolCallID, let toolName, let args):
            try container.encode(EventType.toolExecutionStart, forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(toolName, forKey: .toolName)
            try container.encode(args, forKey: .args)
        case .toolExecutionUpdate(let toolCallID, let toolName, let args, let partialResult):
            try container.encode(EventType.toolExecutionUpdate, forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(toolName, forKey: .toolName)
            try container.encode(args, forKey: .args)
            try container.encode(partialResult, forKey: .partialResult)
        case .toolExecutionEnd(let toolCallID, let toolName, let result, let isError):
            try container.encode(EventType.toolExecutionEnd, forKey: .type)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(toolName, forKey: .toolName)
            try container.encode(result, forKey: .result)
            try container.encode(isError, forKey: .isError)
        }
    }
}
