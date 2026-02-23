import Foundation
import PiAI

public final class PiAgentEventStream: AsyncSequence, @unchecked Sendable {
    public typealias Element = PiAgentEvent

    private final class ContinuationBox {
        var continuation: AsyncStream<Element>.Continuation?
    }

    private let lock = NSLock()
    private let continuationBox: ContinuationBox
    private let stream: AsyncStream<Element>
    private var finalResultContinuation: CheckedContinuation<[PiAgentMessage], Never>?
    private var finalResult: [PiAgentMessage]?
    private var isFinished = false

    public init() {
        let box = ContinuationBox()
        self.continuationBox = box
        self.stream = AsyncStream<Element> { continuation in
            box.continuation = continuation
        }
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        stream.makeAsyncIterator()
    }

    public func push(_ event: PiAgentEvent) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        continuationBox.continuation?.yield(event)
        if case .agentEnd(let messages) = event {
            isFinished = true
            finalResult = messages
            let waiting = finalResultContinuation
            finalResultContinuation = nil
            continuationBox.continuation?.finish()
            lock.unlock()
            waiting?.resume(returning: messages)
            return
        }
        lock.unlock()
    }

    public func end(with result: [PiAgentMessage]? = nil) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        if let result {
            finalResult = result
        }
        let waiting = finalResultContinuation
        finalResultContinuation = nil
        continuationBox.continuation?.finish()
        let final = finalResult
        lock.unlock()
        if let final {
            waiting?.resume(returning: final)
        }
    }

    public func result() async -> [PiAgentMessage] {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let finalResult {
                lock.unlock()
                continuation.resume(returning: finalResult)
                return
            }
            finalResultContinuation = continuation
            lock.unlock()
        }
    }
}

public struct PiAgentLoopConfig: Sendable {
    public typealias ConvertToLLM = @Sendable ([PiAgentMessage]) async throws -> [PiAIMessage]

    public var model: PiAIModel
    public var convertToLLM: ConvertToLLM

    public init(
        model: PiAIModel,
        convertToLLM: ConvertToLLM? = nil
    ) {
        self.model = model
        self.convertToLLM = convertToLLM ?? Self.standardMessageConverter
    }

    public static func standardMessageConverter(_ messages: [PiAgentMessage]) async throws -> [PiAIMessage] {
        try messages.map { message in
            guard let converted = message.asAIMessage else {
                throw PiAgentLoopError.unconvertibleAgentMessageRole(message.role)
            }
            return converted
        }
    }
}

public enum PiAgentLoopError: Error, Equatable, Sendable {
    case unconvertibleAgentMessageRole(String)
}

public enum PiAgentLoop {
    public typealias AssistantStreamFactory = @Sendable (PiAIModel, PiAIContext) async throws -> PiAIAssistantMessageEventStream

    public static func runSingleTurn(
        prompts: [PiAgentMessage],
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        assistantStreamFactory: @escaping AssistantStreamFactory
    ) -> PiAgentEventStream {
        let stream = PiAgentEventStream()

        Task {
            var emittedMessages: [PiAgentMessage] = []
            var currentMessages = context.messages

            stream.push(.agentStart)
            stream.push(.turnStart)

            for prompt in prompts {
                currentMessages.append(prompt)
                emittedMessages.append(prompt)
                stream.push(.messageStart(message: prompt))
                stream.push(.messageEnd(message: prompt))
            }

            do {
                let assistant = try await streamAssistantResponse(
                    systemPrompt: context.systemPrompt,
                    tools: context.tools,
                    messages: &currentMessages,
                    config: config,
                    stream: stream,
                    assistantStreamFactory: assistantStreamFactory
                )

                let assistantMessage = PiAgentMessage.assistant(assistant)
                emittedMessages.append(assistantMessage)
                stream.push(.turnEnd(message: assistantMessage, toolResults: []))
                stream.push(.agentEnd(messages: emittedMessages))
            } catch {
                let errorAssistant = makeErrorAssistantMessage(model: config.model, error: error)
                let errorMessage = PiAgentMessage.assistant(errorAssistant)
                emittedMessages.append(errorMessage)
                stream.push(.messageStart(message: errorMessage))
                stream.push(.messageEnd(message: errorMessage))
                stream.push(.turnEnd(message: errorMessage, toolResults: []))
                stream.push(.agentEnd(messages: emittedMessages))
            }
        }

        return stream
    }

    private static func streamAssistantResponse(
        systemPrompt: String,
        tools: [PiAgentTool]?,
        messages: inout [PiAgentMessage],
        config: PiAgentLoopConfig,
        stream: PiAgentEventStream,
        assistantStreamFactory: AssistantStreamFactory
    ) async throws -> PiAIAssistantMessage {
        let llmMessages = try await config.convertToLLM(messages)
        let aiContext = PiAIContext(
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            messages: llmMessages,
            tools: tools?.map(\.asAITool)
        )

        let assistantStream = try await assistantStreamFactory(config.model, aiContext)
        var addedPartial = false

        for await event in assistantStream {
            switch event {
            case .start(let partial):
                let partialMessage = PiAgentMessage.assistant(partial)
                messages.append(partialMessage)
                addedPartial = true
                stream.push(.messageStart(message: partialMessage))

            case .textStart, .textDelta, .textEnd, .thinkingStart, .thinkingDelta, .thinkingEnd, .toolCallStart, .toolCallDelta, .toolCallEnd:
                let partial = partialMessage(from: event)
                let partialAgentMessage = PiAgentMessage.assistant(partial)
                if addedPartial, !messages.isEmpty {
                    messages[messages.count - 1] = partialAgentMessage
                } else {
                    messages.append(partialAgentMessage)
                    addedPartial = true
                    stream.push(.messageStart(message: partialAgentMessage))
                }
                stream.push(.messageUpdate(message: partialAgentMessage, assistantMessageEvent: event))

            case .done, .error:
                let finalMessage = await assistantStream.result()
                let finalAgentMessage = PiAgentMessage.assistant(finalMessage)
                if addedPartial, !messages.isEmpty {
                    messages[messages.count - 1] = finalAgentMessage
                } else {
                    messages.append(finalAgentMessage)
                    stream.push(.messageStart(message: finalAgentMessage))
                }
                stream.push(.messageEnd(message: finalAgentMessage))
                return finalMessage
            }
        }

        let finalMessage = await assistantStream.result()
        let finalAgentMessage = PiAgentMessage.assistant(finalMessage)
        if addedPartial, !messages.isEmpty {
            messages[messages.count - 1] = finalAgentMessage
        } else {
            messages.append(finalAgentMessage)
            stream.push(.messageStart(message: finalAgentMessage))
        }
        stream.push(.messageEnd(message: finalAgentMessage))
        return finalMessage
    }

    private static func partialMessage(from event: PiAIAssistantMessageEvent) -> PiAIAssistantMessage {
        switch event {
        case .start(let partial):
            return partial
        case .textStart(_, let partial),
             .textDelta(_, _, let partial),
             .textEnd(_, _, let partial),
             .thinkingStart(_, let partial),
             .thinkingDelta(_, _, let partial),
             .thinkingEnd(_, _, let partial),
             .toolCallStart(_, let partial),
             .toolCallDelta(_, _, let partial),
             .toolCallEnd(_, _, let partial):
            return partial
        case .done(_, let message):
            return message
        case .error(_, let error):
            return error
        }
    }

    private static func makeErrorAssistantMessage(model: PiAIModel, error: Error) -> PiAIAssistantMessage {
        PiAIAssistantMessage(
            content: [],
            api: "agent-loop",
            provider: model.provider,
            model: model.id,
            usage: .zero,
            stopReason: .error,
            errorMessage: String(describing: error),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}
