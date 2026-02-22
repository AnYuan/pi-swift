import Foundation
import PiCoreTypes

public enum PiAIOpenAIResponsesOutputItem: Equatable, Sendable {
    case message
    case functionCall(id: String, name: String, arguments: String)
}

public enum PiAIOpenAIResponsesRawEvent: Equatable, Sendable {
    case responseOutputItemAdded(item: PiAIOpenAIResponsesOutputItem)
    case responseOutputTextDelta(delta: String)
    case responseFunctionCallArgumentsDelta(delta: String)
    case responseFunctionCallArgumentsDone
    case responseCompleted(stopReason: PiAIStopReason, usage: PiAIUsage)
}

public enum PiAIOpenAIResponsesSourceError: Error, Equatable, Sendable {
    case mocked(String)
}

public struct PiAIOpenAIResponsesModel: Equatable, Sendable {
    public var provider: String
    public var id: String
    public var api: String

    public init(provider: String = "openai", id: String, api: String = "openai-responses") {
        self.provider = provider
        self.id = id
        self.api = api
    }
}

public struct PiAIOpenAIResponsesProvider: Sendable {
    public typealias MockSource = @Sendable () async throws -> [PiAIOpenAIResponsesRawEvent]

    public init() {}

    public func streamMock(
        model: PiAIOpenAIResponsesModel,
        context: PiAIContext,
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
                var processor = PiAIOpenAIResponsesEventProcessor(output: output, stream: stream)
                stream.push(.start(partial: processor.output))
                let events = try await source()
                for event in events {
                    try processor.apply(event)
                }
                // Ensure stream is closed if the event list forgot to include completion.
                stream.end(with: processor.output)
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
                stream.push(.error(reason: .error, error: errorOutput))
            }

            _ = context // Reserved for future conversion into provider request payload.
        }

        return stream
    }

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

private struct PiAIOpenAIResponsesEventProcessor {
    var output: PiAIAssistantMessage
    let stream: PiAIAssistantMessageEventStream

    private var currentTextBlockIndex: Int?
    private var currentToolCallBlockIndex: Int?
    private var currentToolCallPartialJSON = ""

    init(output: PiAIAssistantMessage, stream: PiAIAssistantMessageEventStream) {
        self.output = output
        self.stream = stream
    }

    mutating func apply(_ event: PiAIOpenAIResponsesRawEvent) throws {
        switch event {
        case .responseOutputItemAdded(let item):
            try handleOutputItemAdded(item)
        case .responseOutputTextDelta(let delta):
            try handleOutputTextDelta(delta)
        case .responseFunctionCallArgumentsDelta(let delta):
            try handleFunctionCallArgumentsDelta(delta)
        case .responseFunctionCallArgumentsDone:
            try handleFunctionCallArgumentsDone()
        case .responseCompleted(let stopReason, let usage):
            output.stopReason = stopReason
            output.usage = usage
            stream.push(.done(reason: stopReason, message: output))
        }
    }

    private mutating func handleOutputItemAdded(_ item: PiAIOpenAIResponsesOutputItem) throws {
        switch item {
        case .message:
            output.content.append(.text(.init(text: "")))
            currentTextBlockIndex = output.content.count - 1
            currentToolCallBlockIndex = nil
            currentToolCallPartialJSON = ""
            stream.push(.textStart(contentIndex: currentTextBlockIndex!, partial: output))

        case .functionCall(let id, let name, let arguments):
            currentToolCallPartialJSON = arguments
            let initialArgs = extractJSONObject(PiAIJSON.parseStreamingJSON(arguments))
            output.content.append(.toolCall(.init(id: id, name: name, arguments: initialArgs)))
            currentToolCallBlockIndex = output.content.count - 1
            currentTextBlockIndex = nil
            stream.push(.toolCallStart(contentIndex: currentToolCallBlockIndex!, partial: output))
        }
    }

    private mutating func handleOutputTextDelta(_ delta: String) throws {
        guard let index = currentTextBlockIndex else { return }
        guard case .text(var textBlock) = output.content[index] else { return }
        textBlock.text += delta
        output.content[index] = .text(textBlock)
        stream.push(.textDelta(contentIndex: index, delta: delta, partial: output))
    }

    private mutating func handleFunctionCallArgumentsDelta(_ delta: String) throws {
        guard let index = currentToolCallBlockIndex else { return }
        guard case .toolCall(var toolCall) = output.content[index] else { return }

        currentToolCallPartialJSON += delta
        toolCall.arguments = extractJSONObject(PiAIJSON.parseStreamingJSON(currentToolCallPartialJSON))
        output.content[index] = .toolCall(toolCall)

        stream.push(.toolCallDelta(contentIndex: index, delta: delta, partial: output))
    }

    private mutating func handleFunctionCallArgumentsDone() throws {
        guard let index = currentToolCallBlockIndex else { return }
        guard case .toolCall(var toolCall) = output.content[index] else { return }

        toolCall.arguments = extractJSONObject(PiAIJSON.parseStreamingJSON(currentToolCallPartialJSON))
        output.content[index] = .toolCall(toolCall)
        stream.push(.toolCallEnd(contentIndex: index, toolCall: toolCall, partial: output))
    }

    private func extractJSONObject(_ value: JSONValue) -> [String: JSONValue] {
        if case .object(let object) = value {
            return object
        }
        return [:]
    }
}

