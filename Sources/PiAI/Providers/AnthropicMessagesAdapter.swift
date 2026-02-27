import Foundation
import PiCoreTypes

public enum PiAIAnthropicMessagesContentBlockStart: Equatable, Sendable {
    case text
    case thinking
    case toolUse(id: String, name: String, input: [String: JSONValue])
}

public enum PiAIAnthropicMessagesContentBlockDelta: Equatable, Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case inputJSONDelta(String)
    case signatureDelta(String)
}

public enum PiAIAnthropicMessagesStopReason: Equatable, Sendable {
    case endTurn
    case maxTokens
    case toolUse
    case refusal
    case pauseTurn
    case stopSequence
    case sensitive
    case unknown(String)
}

public struct PiAIAnthropicMessagesUsageUpdate: Equatable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadInputTokens: Int?
    public var cacheCreationInputTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }
}

public struct PiAIAnthropicMessagesMessageDelta: Equatable, Sendable {
    public var stopReason: PiAIAnthropicMessagesStopReason?

    public init(stopReason: PiAIAnthropicMessagesStopReason? = nil) {
        self.stopReason = stopReason
    }
}

public enum PiAIAnthropicMessagesRawEvent: Equatable, Sendable {
    case messageStart(usage: PiAIAnthropicMessagesUsageUpdate)
    case contentBlockStart(index: Int, block: PiAIAnthropicMessagesContentBlockStart)
    case contentBlockDelta(index: Int, delta: PiAIAnthropicMessagesContentBlockDelta)
    case contentBlockStop(index: Int)
    case messageDelta(delta: PiAIAnthropicMessagesMessageDelta, usage: PiAIAnthropicMessagesUsageUpdate)
    case messageStop
}

public enum PiAIAnthropicMessagesSourceError: Error, Equatable, Sendable {
    case mocked(String)
}

public struct PiAIAnthropicMessagesModel: Equatable, Sendable {
    public var provider: String
    public var id: String
    public var api: String

    public init(provider: String = "anthropic", id: String, api: String = "anthropic-messages") {
        self.provider = provider
        self.id = id
        self.api = api
    }
}

public struct PiAIAnthropicMessagesProvider: Sendable {
    public typealias MockSource = @Sendable () async throws -> [PiAIAnthropicMessagesRawEvent]

    public init() {}

    public func streamMock(
        model: PiAIAnthropicMessagesModel,
        context: PiAIContext,
        oauthToolNaming: Bool = false,
        source: @escaping MockSource
    ) -> PiAIAssistantMessageEventStream {
        let stream = PiAIAssistantMessageEventStream()

        Task {
            let output = PiAIAssistantMessage(
                content: [],
                api: model.api,
                provider: model.provider,
                model: model.id,
                usage: .zero,
                stopReason: .stop,
                timestamp: currentTimestamp()
            )

            do {
                var processor = PiAIAnthropicMessagesEventProcessor(
                    output: output,
                    stream: stream,
                    context: context,
                    oauthToolNaming: oauthToolNaming
                )
                await stream.push(.start(partial: processor.output))

                let events = try await source()
                for event in events {
                    try await processor.apply(event)
                }

                // Safety net when the mock source omits a terminal event.
                await stream.end(with: processor.output)
            } catch {
                let message = errorMessage(error)
                let errorOutput = PiAIAssistantMessage(
                    content: [],
                    api: model.api,
                    provider: model.provider,
                    model: model.id,
                    usage: .zero,
                    stopReason: .error,
                    errorMessage: message,
                    timestamp: currentTimestamp()
                )
                await stream.push(.error(reason: .error, error: errorOutput))
            }
        }

        return stream
    }

    static func normalizeOutboundToolNameForOAuth(_ name: String) -> String {
        Self.claudeCodeToolLookup[name.lowercased()] ?? name
    }

    static func normalizeInboundToolNameFromOAuth(_ name: String, tools: [PiAITool]?) -> String {
        guard let tools, !tools.isEmpty else {
            return name
        }
        let lower = name.lowercased()
        if let match = tools.first(where: { $0.name.lowercased() == lower }) {
            return match.name
        }
        return name
    }

    private static let claudeCodeToolNames = [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Grep",
        "Glob",
        "AskUserQuestion",
        "EnterPlanMode",
        "ExitPlanMode",
        "KillShell",
        "NotebookEdit",
        "Skill",
        "Task",
        "TaskOutput",
        "TodoWrite",
        "WebFetch",
        "WebSearch",
    ]

    private static let claudeCodeToolLookup: [String: String] = {
        Dictionary(uniqueKeysWithValues: claudeCodeToolNames.map { ($0.lowercased(), $0) })
    }()

    private func currentTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private enum PiAIAnthropicMessagesProcessorError: Error {
    case unhandledStopReason(String)
}

private struct PiAIAnthropicMessagesEventProcessor {
    var output: PiAIAssistantMessage
    let stream: PiAIAssistantMessageEventStream
    let context: PiAIContext
    let oauthToolNaming: Bool

    private var anthropicIndexToContentIndex: [Int: Int] = [:]
    private var toolCallPartialJSONByContentIndex: [Int: String] = [:]

    init(
        output: PiAIAssistantMessage,
        stream: PiAIAssistantMessageEventStream,
        context: PiAIContext,
        oauthToolNaming: Bool
    ) {
        self.output = output
        self.stream = stream
        self.context = context
        self.oauthToolNaming = oauthToolNaming
    }

    mutating func apply(_ event: PiAIAnthropicMessagesRawEvent) async throws {
        switch event {
        case .messageStart(let usage):
            applyUsageUpdate(usage)
        case .contentBlockStart(let index, let block):
            try await handleContentBlockStart(index: index, block: block)
        case .contentBlockDelta(let index, let delta):
            try await handleContentBlockDelta(index: index, delta: delta)
        case .contentBlockStop(let index):
            try await handleContentBlockStop(index: index)
        case .messageDelta(let delta, let usage):
            try handleMessageDelta(delta: delta, usage: usage)
        case .messageStop:
            if output.stopReason == .error || output.stopReason == .aborted {
                throw PiAIAnthropicMessagesProcessorError.unhandledStopReason(output.stopReason.rawValue)
            }
            await stream.push(.done(reason: output.stopReason, message: output))
        }
    }

    private mutating func applyUsageUpdate(_ usage: PiAIAnthropicMessagesUsageUpdate) {
        if let inputTokens = usage.inputTokens {
            output.usage.input = inputTokens
        }
        if let outputTokens = usage.outputTokens {
            output.usage.output = outputTokens
        }
        if let cacheRead = usage.cacheReadInputTokens {
            output.usage.cacheRead = cacheRead
        }
        if let cacheWrite = usage.cacheCreationInputTokens {
            output.usage.cacheWrite = cacheWrite
        }
        output.usage.totalTokens = output.usage.input + output.usage.output + output.usage.cacheRead + output.usage.cacheWrite
    }

    private mutating func handleContentBlockStart(index: Int, block: PiAIAnthropicMessagesContentBlockStart) async throws {
        switch block {
        case .text:
            output.content.append(.text(.init(text: "")))
            let contentIndex = output.content.count - 1
            anthropicIndexToContentIndex[index] = contentIndex
            await stream.push(.textStart(contentIndex: contentIndex, partial: output))

        case .thinking:
            output.content.append(.thinking(.init(thinking: "", thinkingSignature: nil)))
            let contentIndex = output.content.count - 1
            anthropicIndexToContentIndex[index] = contentIndex
            await stream.push(.thinkingStart(contentIndex: contentIndex, partial: output))

        case .toolUse(let id, let name, let input):
            let normalizedName: String
            if oauthToolNaming {
                normalizedName = PiAIAnthropicMessagesProvider.normalizeInboundToolNameFromOAuth(name, tools: context.tools)
            } else {
                normalizedName = name
            }

            output.content.append(.toolCall(.init(id: id, name: normalizedName, arguments: input)))
            let contentIndex = output.content.count - 1
            anthropicIndexToContentIndex[index] = contentIndex
            toolCallPartialJSONByContentIndex[contentIndex] = ""
            await stream.push(.toolCallStart(contentIndex: contentIndex, partial: output))
        }
    }

    private mutating func handleContentBlockDelta(index: Int, delta: PiAIAnthropicMessagesContentBlockDelta) async throws {
        guard let contentIndex = anthropicIndexToContentIndex[index] else { return }
        guard output.content.indices.contains(contentIndex) else { return }

        switch delta {
        case .textDelta(let chunk):
            guard case .text(var textBlock) = output.content[contentIndex] else { return }
            textBlock.text += chunk
            output.content[contentIndex] = .text(textBlock)
            await stream.push(.textDelta(contentIndex: contentIndex, delta: chunk, partial: output))

        case .thinkingDelta(let chunk):
            guard case .thinking(var thinkingBlock) = output.content[contentIndex] else { return }
            thinkingBlock.thinking += chunk
            output.content[contentIndex] = .thinking(thinkingBlock)
            await stream.push(.thinkingDelta(contentIndex: contentIndex, delta: chunk, partial: output))

        case .signatureDelta(let signature):
            guard case .thinking(var thinkingBlock) = output.content[contentIndex] else { return }
            thinkingBlock.thinkingSignature = (thinkingBlock.thinkingSignature ?? "") + signature
            output.content[contentIndex] = .thinking(thinkingBlock)

        case .inputJSONDelta(let partialJSON):
            guard case .toolCall(var toolCall) = output.content[contentIndex] else { return }
            let updated = (toolCallPartialJSONByContentIndex[contentIndex] ?? "") + partialJSON
            toolCallPartialJSONByContentIndex[contentIndex] = updated
            toolCall.arguments = extractJSONObject(PiAIJSON.parseStreamingJSON(updated))
            output.content[contentIndex] = .toolCall(toolCall)
            await stream.push(.toolCallDelta(contentIndex: contentIndex, delta: partialJSON, partial: output))
        }
    }

    private mutating func handleContentBlockStop(index: Int) async throws {
        guard let contentIndex = anthropicIndexToContentIndex.removeValue(forKey: index) else { return }
        guard output.content.indices.contains(contentIndex) else { return }

        switch output.content[contentIndex] {
        case .text(let text):
            await stream.push(.textEnd(contentIndex: contentIndex, content: text.text, partial: output))

        case .thinking(let thinking):
            await stream.push(.thinkingEnd(contentIndex: contentIndex, content: thinking.thinking, partial: output))

        case .toolCall(var toolCall):
            if let partial = toolCallPartialJSONByContentIndex.removeValue(forKey: contentIndex), !partial.isEmpty {
                toolCall.arguments = extractJSONObject(PiAIJSON.parseStreamingJSON(partial))
                output.content[contentIndex] = .toolCall(toolCall)
            }
            await stream.push(.toolCallEnd(contentIndex: contentIndex, toolCall: toolCall, partial: output))
        }
    }

    private mutating func handleMessageDelta(
        delta: PiAIAnthropicMessagesMessageDelta,
        usage: PiAIAnthropicMessagesUsageUpdate
    ) throws {
        if let stopReason = delta.stopReason {
            output.stopReason = try mapStopReason(stopReason)
        }
        applyUsageUpdate(usage)
    }

    private func mapStopReason(_ reason: PiAIAnthropicMessagesStopReason) throws -> PiAIStopReason {
        switch reason {
        case .endTurn:
            return .stop
        case .maxTokens:
            return .length
        case .toolUse:
            return .toolUse
        case .refusal, .sensitive:
            return .error
        case .pauseTurn, .stopSequence:
            return .stop
        case .unknown(let raw):
            throw PiAIAnthropicMessagesProcessorError.unhandledStopReason(raw)
        }
    }

    private func extractJSONObject(_ value: JSONValue) -> [String: JSONValue] {
        if case .object(let object) = value {
            return object
        }
        return [:]
    }
}
