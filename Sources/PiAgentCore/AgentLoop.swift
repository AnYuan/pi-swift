import Foundation
import PiAI
import PiCoreTypes

public actor PiAgentAbortController {
    private var aborted = false

    public init() {}

    public func abort() {
        aborted = true
    }

    public var isAborted: Bool {
        aborted
    }
}

public actor PiAgentEventStream: AsyncSequence {
    public typealias Element = PiAgentEvent

    // The AsyncStream and its continuation are Sendable and thread-safe.
    // They are set once during init and never mutated.
    private let _continuation: AsyncStream<Element>.Continuation
    nonisolated public let _stream: AsyncStream<Element>

    private var finalResultContinuation: CheckedContinuation<[PiAgentMessage], Never>?
    private var finalResult: [PiAgentMessage]?
    private var isFinished = false

    public init() {
        var cont: AsyncStream<Element>.Continuation!
        self._stream = AsyncStream<Element> { continuation in
            cont = continuation
        }
        self._continuation = cont
    }

    nonisolated public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        _stream.makeAsyncIterator()
    }

    public func push(_ event: PiAgentEvent) {
        guard !isFinished else { return }
        _continuation.yield(event)
        if case .agentEnd(let messages) = event {
            isFinished = true
            finalResult = messages
            let waiting = finalResultContinuation
            finalResultContinuation = nil
            _continuation.finish()
            waiting?.resume(returning: messages)
        }
    }

    public func end(with result: [PiAgentMessage]? = nil) {
        guard !isFinished else { return }
        isFinished = true
        if let result {
            finalResult = result
        }
        let waiting = finalResultContinuation
        finalResultContinuation = nil
        _continuation.finish()
        if let finalResult {
            waiting?.resume(returning: finalResult)
        }
    }

    public func result() async -> [PiAgentMessage] {
        if let finalResult {
            return finalResult
        }
        return await withCheckedContinuation { continuation in
            finalResultContinuation = continuation
        }
    }
}

public struct PiAgentThinkingBudgets: Codable, Equatable, Sendable {
    public var minimal: Int?
    public var low: Int?
    public var medium: Int?
    public var high: Int?

    public init(minimal: Int? = nil, low: Int? = nil, medium: Int? = nil, high: Int? = nil) {
        self.minimal = minimal
        self.low = low
        self.medium = medium
        self.high = high
    }
}

public struct PiAgentLLMRequestOptions: Codable, Equatable, Sendable {
    public var reasoning: PiAgentThinkingLevel?
    public var sessionId: String?
    public var thinkingBudgets: PiAgentThinkingBudgets?

    public init(
        reasoning: PiAgentThinkingLevel? = nil,
        sessionId: String? = nil,
        thinkingBudgets: PiAgentThinkingBudgets? = nil
    ) {
        self.reasoning = reasoning
        self.sessionId = sessionId
        self.thinkingBudgets = thinkingBudgets
    }
}

public struct PiAgentLoopConfig: Sendable {
    public typealias ConvertToLLM = @Sendable ([PiAgentMessage]) async throws -> [PiAIMessage]
    public typealias GetMessages = @Sendable () async -> [PiAgentMessage]
    public typealias TransformContext = @Sendable ([PiAgentMessage], PiAgentAbortController?) async throws -> [PiAgentMessage]

    public var model: PiAIModel
    public var convertToLLM: ConvertToLLM
    public var transformContext: TransformContext?
    public var thinkingLevel: PiAgentThinkingLevel
    public var sessionId: String?
    public var thinkingBudgets: PiAgentThinkingBudgets?
    public var getSteeringMessages: GetMessages?
    public var getFollowUpMessages: GetMessages?

    public init(
        model: PiAIModel,
        convertToLLM: ConvertToLLM? = nil,
        transformContext: TransformContext? = nil,
        thinkingLevel: PiAgentThinkingLevel = .off,
        sessionId: String? = nil,
        thinkingBudgets: PiAgentThinkingBudgets? = nil,
        getSteeringMessages: GetMessages? = nil,
        getFollowUpMessages: GetMessages? = nil
    ) {
        self.model = model
        self.convertToLLM = convertToLLM ?? Self.standardMessageConverter
        self.transformContext = transformContext
        self.thinkingLevel = thinkingLevel
        self.sessionId = sessionId
        self.thinkingBudgets = thinkingBudgets
        self.getSteeringMessages = getSteeringMessages
        self.getFollowUpMessages = getFollowUpMessages
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
    case cannotContinueWithoutMessages
    case cannotContinueFromAssistantMessage
    case aborted
}

public struct PiAgentRuntimeTool: Sendable {
    public typealias ProgressCallback = @Sendable (PiAgentToolExecutionResult) -> Void
    public typealias Execute = @Sendable (_ toolCallID: String, _ args: [String: JSONValue], _ abortController: PiAgentAbortController?, _ onProgress: @escaping ProgressCallback) async throws -> PiAgentToolExecutionResult
    public typealias LegacyExecute = @Sendable (_ toolCallID: String, _ args: [String: JSONValue], _ onProgress: @escaping ProgressCallback) async throws -> PiAgentToolExecutionResult

    public var tool: PiAgentTool
    public var execute: Execute

    public init(tool: PiAgentTool, execute: @escaping Execute) {
        self.tool = tool
        self.execute = execute
    }

    public init(tool: PiAgentTool, execute: @escaping LegacyExecute) {
        self.tool = tool
        self.execute = { toolCallID, args, _, onProgress in
            try await execute(toolCallID, args, onProgress)
        }
    }
}

public enum PiAgentLoop {
    public typealias AssistantStreamFactory = @Sendable (PiAIModel, PiAIContext) async throws -> PiAIAssistantMessageEventStream
    public typealias AssistantStreamFactoryWithOptions = @Sendable (PiAIModel, PiAIContext, PiAgentLLMRequestOptions) async throws -> PiAIAssistantMessageEventStream

    public static func run(
        prompts: [PiAgentMessage],
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        runtimeTools: [PiAgentRuntimeTool],
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactory
    ) -> PiAgentEventStream {
        run(
            prompts: prompts,
            context: context,
            config: config,
            runtimeTools: runtimeTools,
            abortController: abortController
        ) { model, aiContext, _ in
            try await assistantStreamFactory(model, aiContext)
        }
    }

    public static func run(
        prompts: [PiAgentMessage],
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        runtimeTools: [PiAgentRuntimeTool],
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactoryWithOptions
    ) -> PiAgentEventStream {
        let stream = PiAgentEventStream()

        Task {
            var emittedMessages: [PiAgentMessage] = []
            var currentMessages = context.messages
            var pendingMessages: [PiAgentMessage] = []

            await stream.push(.agentStart)
            await stream.push(.turnStart)

            for prompt in prompts {
                currentMessages.append(prompt)
                emittedMessages.append(prompt)
                await stream.push(.messageStart(message: prompt))
                await stream.push(.messageEnd(message: prompt))
            }

            do {
                var isFirstTurn = true

                while true {
                    try await throwIfAborted(abortController)
                    if !isFirstTurn {
                        await stream.push(.turnStart)
                    }
                    isFirstTurn = false

                    if !pendingMessages.isEmpty {
                        for message in pendingMessages {
                            currentMessages.append(message)
                            emittedMessages.append(message)
                            await stream.push(.messageStart(message: message))
                            await stream.push(.messageEnd(message: message))
                        }
                        pendingMessages.removeAll(keepingCapacity: true)
                    }

                    let assistant = try await streamAssistantResponse(
                        systemPrompt: context.systemPrompt,
                        tools: context.tools,
                        messages: &currentMessages,
                        config: config,
                        stream: stream,
                        abortController: abortController,
                        assistantStreamFactory: assistantStreamFactory
                    )

                    let assistantAgentMessage = PiAgentMessage.assistant(assistant)
                    emittedMessages.append(assistantAgentMessage)

                    let toolExecution = try await executeToolCalls(
                        from: assistant,
                        runtimeTools: runtimeTools,
                        stream: stream,
                        abortController: abortController,
                        getSteeringMessages: config.getSteeringMessages
                    )
                    let toolResults = toolExecution.toolResults

                    for toolResult in toolResults {
                        let toolResultAgentMessage = PiAgentMessage.toolResult(toolResult)
                        currentMessages.append(toolResultAgentMessage)
                        emittedMessages.append(toolResultAgentMessage)
                    }

                    await stream.push(.turnEnd(message: assistantAgentMessage, toolResults: toolResults))

                    if assistant.stopReason == .error || assistant.stopReason == .aborted {
                        break
                    }

                    if let steeringMessages = toolExecution.steeringMessages, !steeringMessages.isEmpty {
                        pendingMessages = steeringMessages
                        continue
                    }

                    if toolResults.isEmpty {
                        if let followUpMessages = await config.getFollowUpMessages?(), !followUpMessages.isEmpty {
                            pendingMessages = followUpMessages
                            continue
                        }
                        break
                    }
                }

                await stream.push(.agentEnd(messages: emittedMessages))
            } catch {
                let errorAssistant = makeFailureAssistantMessage(model: config.model, error: error)
                let errorMessage = PiAgentMessage.assistant(errorAssistant)
                emittedMessages.append(errorMessage)
                await stream.push(.messageStart(message: errorMessage))
                await stream.push(.messageEnd(message: errorMessage))
                await stream.push(.turnEnd(message: errorMessage, toolResults: []))
                await stream.push(.agentEnd(messages: emittedMessages))
            }
        }

        return stream
    }

    public static func runContinue(
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        runtimeTools: [PiAgentRuntimeTool] = [],
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactory
    ) throws -> PiAgentEventStream {
        try runContinue(
            context: context,
            config: config,
            runtimeTools: runtimeTools,
            abortController: abortController
        ) { model, aiContext, _ in
            try await assistantStreamFactory(model, aiContext)
        }
    }

    public static func runContinue(
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        runtimeTools: [PiAgentRuntimeTool] = [],
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactoryWithOptions
    ) throws -> PiAgentEventStream {
        guard !context.messages.isEmpty else {
            throw PiAgentLoopError.cannotContinueWithoutMessages
        }
        if case .assistant = context.messages.last {
            throw PiAgentLoopError.cannotContinueFromAssistantMessage
        }

        return run(
            prompts: [],
            context: context,
            config: config,
            runtimeTools: runtimeTools,
            abortController: abortController,
            assistantStreamFactory: assistantStreamFactory
        )
    }

    public static func runSingleTurn(
        prompts: [PiAgentMessage],
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactory
    ) -> PiAgentEventStream {
        runSingleTurn(
            prompts: prompts,
            context: context,
            config: config,
            abortController: abortController
        ) { model, aiContext, _ in
            try await assistantStreamFactory(model, aiContext)
        }
    }

    public static func runSingleTurn(
        prompts: [PiAgentMessage],
        context: PiAgentContext,
        config: PiAgentLoopConfig,
        abortController: PiAgentAbortController? = nil,
        assistantStreamFactory: @escaping AssistantStreamFactoryWithOptions
    ) -> PiAgentEventStream {
        let stream = PiAgentEventStream()

        Task {
            var emittedMessages: [PiAgentMessage] = []
            var currentMessages = context.messages

            await stream.push(.agentStart)
            await stream.push(.turnStart)

            for prompt in prompts {
                currentMessages.append(prompt)
                emittedMessages.append(prompt)
                await stream.push(.messageStart(message: prompt))
                await stream.push(.messageEnd(message: prompt))
            }

            do {
                try await throwIfAborted(abortController)
                let assistant = try await streamAssistantResponse(
                    systemPrompt: context.systemPrompt,
                    tools: context.tools,
                    messages: &currentMessages,
                    config: config,
                    stream: stream,
                    abortController: abortController,
                    assistantStreamFactory: assistantStreamFactory
                )

                let assistantMessage = PiAgentMessage.assistant(assistant)
                emittedMessages.append(assistantMessage)
                await stream.push(.turnEnd(message: assistantMessage, toolResults: []))
                await stream.push(.agentEnd(messages: emittedMessages))
            } catch {
                let errorAssistant = makeFailureAssistantMessage(model: config.model, error: error)
                let errorMessage = PiAgentMessage.assistant(errorAssistant)
                emittedMessages.append(errorMessage)
                await stream.push(.messageStart(message: errorMessage))
                await stream.push(.messageEnd(message: errorMessage))
                await stream.push(.turnEnd(message: errorMessage, toolResults: []))
                await stream.push(.agentEnd(messages: emittedMessages))
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
        abortController: PiAgentAbortController?,
        assistantStreamFactory: AssistantStreamFactoryWithOptions
    ) async throws -> PiAIAssistantMessage {
        try await throwIfAborted(abortController)
        let transformedMessages: [PiAgentMessage]
        if let transformContext = config.transformContext {
            transformedMessages = try await transformContext(messages, abortController)
        } else {
            transformedMessages = messages
        }
        try await throwIfAborted(abortController)
        let llmMessages = try await config.convertToLLM(transformedMessages)
        let aiContext = PiAIContext(
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            messages: llmMessages,
            tools: tools?.map(\.asAITool)
        )

        try await throwIfAborted(abortController)
        let assistantStream = try await assistantStreamFactory(config.model, aiContext, makeLLMRequestOptions(config: config))
        var addedPartial = false

        for await event in assistantStream {
            try await throwIfAborted(abortController)
            switch event {
            case .start(let partial):
                let partialMessage = PiAgentMessage.assistant(partial)
                messages.append(partialMessage)
                addedPartial = true
                await stream.push(.messageStart(message: partialMessage))

            case .textStart, .textDelta, .textEnd, .thinkingStart, .thinkingDelta, .thinkingEnd, .toolCallStart, .toolCallDelta, .toolCallEnd:
                let partial = partialMessage(from: event)
                let partialAgentMessage = PiAgentMessage.assistant(partial)
                if addedPartial, !messages.isEmpty {
                    messages[messages.count - 1] = partialAgentMessage
                } else {
                    messages.append(partialAgentMessage)
                    addedPartial = true
                    await stream.push(.messageStart(message: partialAgentMessage))
                }
                await stream.push(.messageUpdate(message: partialAgentMessage, assistantMessageEvent: event))

            case .done, .error:
                let finalMessage = await assistantStream.result()
                let finalAgentMessage = PiAgentMessage.assistant(finalMessage)
                if addedPartial, !messages.isEmpty {
                    messages[messages.count - 1] = finalAgentMessage
                } else {
                    messages.append(finalAgentMessage)
                    await stream.push(.messageStart(message: finalAgentMessage))
                }
                await stream.push(.messageEnd(message: finalAgentMessage))
                return finalMessage
            }
        }

        let finalMessage = await assistantStream.result()
        let finalAgentMessage = PiAgentMessage.assistant(finalMessage)
        if addedPartial, !messages.isEmpty {
            messages[messages.count - 1] = finalAgentMessage
        } else {
            messages.append(finalAgentMessage)
            await stream.push(.messageStart(message: finalAgentMessage))
        }
        await stream.push(.messageEnd(message: finalAgentMessage))
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

    private static func makeFailureAssistantMessage(model: PiAIModel, error: Error) -> PiAIAssistantMessage {
        let stopReason: PiAIStopReason
        if let loopError = error as? PiAgentLoopError, loopError == .aborted {
            stopReason = .aborted
        } else {
            stopReason = .error
        }
        return PiAIAssistantMessage(
            content: [],
            api: "agent-loop",
            provider: model.provider,
            model: model.id,
            usage: .zero,
            stopReason: stopReason,
            errorMessage: String(describing: error),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    private static func executeToolCalls(
        from assistantMessage: PiAIAssistantMessage,
        runtimeTools: [PiAgentRuntimeTool],
        stream: PiAgentEventStream,
        abortController: PiAgentAbortController?,
        getSteeringMessages: PiAgentLoopConfig.GetMessages?
    ) async throws -> (toolResults: [PiAIToolResultMessage], steeringMessages: [PiAgentMessage]?) {
        let toolCalls = assistantMessage.content.compactMap { part -> PiAIToolCallContent? in
            guard case .toolCall(let toolCall) = part else { return nil }
            return toolCall
        }

        guard !toolCalls.isEmpty else {
            return ([], nil)
        }

        // When steering is active, execute sequentially to support early-break.
        // When steering is not active and there are multiple tool calls, execute
        // concurrently for performance.
        if getSteeringMessages != nil || toolCalls.count == 1 {
            return try await executeToolCallsSequentially(
                toolCalls: toolCalls,
                runtimeTools: runtimeTools,
                stream: stream,
                abortController: abortController,
                getSteeringMessages: getSteeringMessages
            )
        } else {
            return try await executeToolCallsInParallel(
                toolCalls: toolCalls,
                runtimeTools: runtimeTools,
                stream: stream,
                abortController: abortController
            )
        }
    }

    private static func executeToolCallsSequentially(
        toolCalls: [PiAIToolCallContent],
        runtimeTools: [PiAgentRuntimeTool],
        stream: PiAgentEventStream,
        abortController: PiAgentAbortController?,
        getSteeringMessages: PiAgentLoopConfig.GetMessages?
    ) async throws -> (toolResults: [PiAIToolResultMessage], steeringMessages: [PiAgentMessage]?) {
        var results: [PiAIToolResultMessage] = []
        var steeringMessages: [PiAgentMessage]?

        for (index, toolCall) in toolCalls.enumerated() {
            try await throwIfAborted(abortController)
            let (toolResultMessage, _) = try await executeSingleToolCall(
                toolCall: toolCall, runtimeTools: runtimeTools,
                stream: stream, abortController: abortController
            )
            results.append(toolResultMessage)

            if let getSteeringMessages {
                let steering = await getSteeringMessages()
                if !steering.isEmpty {
                    steeringMessages = steering
                    if index < toolCalls.count - 1 {
                        for skippedCall in toolCalls[(index + 1)...] {
                            let skipped = await skipToolCall(skippedCall, stream: stream)
                            results.append(skipped)
                        }
                    }
                    break
                }
            }
        }

        return (results, steeringMessages)
    }

    private static func executeToolCallsInParallel(
        toolCalls: [PiAIToolCallContent],
        runtimeTools: [PiAgentRuntimeTool],
        stream: PiAgentEventStream,
        abortController: PiAgentAbortController?
    ) async throws -> (toolResults: [PiAIToolResultMessage], steeringMessages: [PiAgentMessage]?) {
        // Execute all tool calls concurrently, collecting results indexed by position
        let indexedResults: [(Int, PiAIToolResultMessage, [PiAgentEvent])] = try await withThrowingTaskGroup(
            of: (Int, PiAIToolResultMessage, [PiAgentEvent]).self
        ) { group in
            for (index, toolCall) in toolCalls.enumerated() {
                group.addTask {
                    try await throwIfAborted(abortController)
                    let (result, events) = try await executeSingleToolCallBuffered(
                        toolCall: toolCall, runtimeTools: runtimeTools,
                        abortController: abortController
                    )
                    return (index, result, events)
                }
            }

            var collected: [(Int, PiAIToolResultMessage, [PiAgentEvent])] = []
            for try await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        // Emit events in original tool call order after all complete
        var results: [PiAIToolResultMessage] = []
        for (_, toolResultMessage, events) in indexedResults {
            for event in events {
                await stream.push(event)
            }
            results.append(toolResultMessage)
        }

        return (results, nil)
    }

    /// Executes a single tool call, pushing events directly to the stream.
    private static func executeSingleToolCall(
        toolCall: PiAIToolCallContent,
        runtimeTools: [PiAgentRuntimeTool],
        stream: PiAgentEventStream,
        abortController: PiAgentAbortController?
    ) async throws -> (PiAIToolResultMessage, [PiAgentEvent]) {
        await stream.push(.toolExecutionStart(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            args: .object(toolCall.arguments)
        ))

        let executionResult: PiAgentToolExecutionResult
        let isError: Bool

        do {
            guard let runtimeTool = runtimeTools.first(where: { $0.tool.name == toolCall.name }) else {
                throw PiAIValidationError("Tool \"\(toolCall.name)\" not found")
            }
            let validatedArgs = try PiAIValidation.validateToolArguments(tool: runtimeTool.tool.asAITool, toolCall: toolCall)
            executionResult = try await runtimeTool.execute(toolCall.id, validatedArgs, abortController) { partialResult in
                Task {
                    await stream.push(.toolExecutionUpdate(
                        toolCallID: toolCall.id,
                        toolName: toolCall.name,
                        args: .object(toolCall.arguments),
                        partialResult: partialResult
                    ))
                }
            }
            isError = false
        } catch {
            executionResult = PiAgentToolExecutionResult(
                content: [.text(.init(text: String(describing: error)))],
                details: .object([:])
            )
            isError = true
        }

        await stream.push(.toolExecutionEnd(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            result: executionResult,
            isError: isError
        ))

        let toolResultMessage = PiAIToolResultMessage(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            content: executionResult.content,
            details: executionResult.details,
            isError: isError,
            timestamp: currentTimestampMillis()
        )

        let agentMessage = PiAgentMessage.toolResult(toolResultMessage)
        await stream.push(.messageStart(message: agentMessage))
        await stream.push(.messageEnd(message: agentMessage))

        return (toolResultMessage, [])
    }

    /// Executes a single tool call for parallel mode — returns buffered events
    /// instead of pushing to stream, so they can be emitted in order later.
    private static func executeSingleToolCallBuffered(
        toolCall: PiAIToolCallContent,
        runtimeTools: [PiAgentRuntimeTool],
        abortController: PiAgentAbortController?
    ) async throws -> (PiAIToolResultMessage, [PiAgentEvent]) {
        var events: [PiAgentEvent] = []

        events.append(.toolExecutionStart(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            args: .object(toolCall.arguments)
        ))

        let executionResult: PiAgentToolExecutionResult
        let isError: Bool

        do {
            guard let runtimeTool = runtimeTools.first(where: { $0.tool.name == toolCall.name }) else {
                throw PiAIValidationError("Tool \"\(toolCall.name)\" not found")
            }
            let validatedArgs = try PiAIValidation.validateToolArguments(tool: runtimeTool.tool.asAITool, toolCall: toolCall)
            executionResult = try await runtimeTool.execute(toolCall.id, validatedArgs, abortController) { _ in
                // Progress updates are not emitted in parallel mode to avoid
                // interleaved event ordering across concurrent tool calls
            }
            isError = false
        } catch {
            executionResult = PiAgentToolExecutionResult(
                content: [.text(.init(text: String(describing: error)))],
                details: .object([:])
            )
            isError = true
        }

        events.append(.toolExecutionEnd(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            result: executionResult,
            isError: isError
        ))

        let toolResultMessage = PiAIToolResultMessage(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            content: executionResult.content,
            details: executionResult.details,
            isError: isError,
            timestamp: currentTimestampMillis()
        )

        let agentMessage = PiAgentMessage.toolResult(toolResultMessage)
        events.append(.messageStart(message: agentMessage))
        events.append(.messageEnd(message: agentMessage))

        return (toolResultMessage, events)
    }

    private static func throwIfAborted(_ abortController: PiAgentAbortController?) async throws {
        if let abortController, await abortController.isAborted {
            throw PiAgentLoopError.aborted
        }
    }

    private static func makeLLMRequestOptions(config: PiAgentLoopConfig) -> PiAgentLLMRequestOptions {
        let reasoning: PiAgentThinkingLevel? = config.thinkingLevel == .off ? nil : config.thinkingLevel
        return PiAgentLLMRequestOptions(
            reasoning: reasoning,
            sessionId: config.sessionId,
            thinkingBudgets: config.thinkingBudgets
        )
    }

    private static func currentTimestampMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func skipToolCall(
        _ toolCall: PiAIToolCallContent,
        stream: PiAgentEventStream
    ) async -> PiAIToolResultMessage {
        let result = PiAgentToolExecutionResult(
            content: [.text(.init(text: "Skipped due to queued user message."))],
            details: .object([:])
        )

        await stream.push(.toolExecutionStart(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            args: .object(toolCall.arguments)
        ))
        await stream.push(.toolExecutionEnd(
            toolCallID: toolCall.id,
            toolName: toolCall.name,
            result: result,
            isError: true
        ))

        let toolResultMessage = PiAIToolResultMessage(
            toolCallId: toolCall.id,
            toolName: toolCall.name,
            content: result.content,
            details: .object([:]),
            isError: true,
            timestamp: currentTimestampMillis()
        )
        let agentMessage = PiAgentMessage.toolResult(toolResultMessage)
        await stream.push(.messageStart(message: agentMessage))
        await stream.push(.messageEnd(message: agentMessage))
        return toolResultMessage
    }
}
