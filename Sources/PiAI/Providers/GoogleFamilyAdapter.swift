import Foundation
import PiCoreTypes

public enum PiAIGoogleStreamingSemantics {
    public static func isThinkingPart(thought: Bool?, thoughtSignature: String?) -> Bool {
        _ = thoughtSignature // Signature alone does not imply thinking.
        return thought == true
    }

    public static func retainThoughtSignature(existing: String?, incoming: String?) -> String? {
        if let incoming, !incoming.isEmpty {
            return incoming
        }
        return existing
    }
}

public enum PiAIGoogleFinishReason: Equatable, Sendable {
    case stop
    case maxTokens
    case safety
    case recitation
    case blocked
    case other(String)
}

public enum PiAIGooglePart: Equatable, Sendable {
    case text(text: String, thought: Bool?, thoughtSignature: String?)
    case functionCall(name: String, id: String?, args: [String: JSONValue]?, thoughtSignature: String?)
}

public struct PiAIGoogleUsageMetadata: Equatable, Sendable {
    public var promptTokenCount: Int
    public var candidatesTokenCount: Int
    public var thoughtsTokenCount: Int
    public var cachedContentTokenCount: Int
    public var totalTokenCount: Int

    public init(
        promptTokenCount: Int,
        candidatesTokenCount: Int,
        thoughtsTokenCount: Int,
        cachedContentTokenCount: Int,
        totalTokenCount: Int
    ) {
        self.promptTokenCount = promptTokenCount
        self.candidatesTokenCount = candidatesTokenCount
        self.thoughtsTokenCount = thoughtsTokenCount
        self.cachedContentTokenCount = cachedContentTokenCount
        self.totalTokenCount = totalTokenCount
    }
}

public struct PiAIGoogleRawChunk: Equatable, Sendable {
    public var parts: [PiAIGooglePart]
    public var finishReason: PiAIGoogleFinishReason?
    public var usage: PiAIGoogleUsageMetadata?

    public init(parts: [PiAIGooglePart], finishReason: PiAIGoogleFinishReason? = nil, usage: PiAIGoogleUsageMetadata? = nil) {
        self.parts = parts
        self.finishReason = finishReason
        self.usage = usage
    }
}

public enum PiAIGoogleFamilySourceError: Error, Equatable, Sendable {
    case mocked(String)
    case emptyStreamAfterRetries(Int)
}

public struct PiAIGoogleFamilyModel: Equatable, Sendable {
    public var provider: String
    public var id: String
    public var api: String

    public init(provider: String, id: String, api: String) {
        self.provider = provider
        self.id = id
        self.api = api
    }
}

public struct PiAIGoogleFamilyProvider: Sendable {
    public typealias MockSource = @Sendable () async throws -> [PiAIGoogleRawChunk]
    public typealias MockAttemptsSource = @Sendable () async throws -> [[PiAIGoogleRawChunk]]

    public init() {}

    public func streamMock(
        model: PiAIGoogleFamilyModel,
        context: PiAIContext,
        source: @escaping MockSource
    ) -> PiAIAssistantMessageEventStream {
        streamMockRetryingEmptyAttempts(model: model, context: context, maxAttempts: 1) {
            [try await source()]
        }
    }

    public func streamMockRetryingEmptyAttempts(
        model: PiAIGoogleFamilyModel,
        context: PiAIContext,
        maxAttempts: Int,
        source: @escaping MockAttemptsSource
    ) -> PiAIAssistantMessageEventStream {
        let stream = PiAIAssistantMessageEventStream()

        Task {
            do {
                let attempts = try await source()
                let final = try processAttempts(
                    attempts,
                    model: model,
                    context: context,
                    maxAttempts: maxAttempts,
                    stream: stream
                )
                _ = final
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
        }

        return stream
    }

    private func processAttempts(
        _ attempts: [[PiAIGoogleRawChunk]],
        model: PiAIGoogleFamilyModel,
        context: PiAIContext,
        maxAttempts: Int,
        stream: PiAIAssistantMessageEventStream
    ) throws -> PiAIAssistantMessage {
        let cappedMaxAttempts = max(1, maxAttempts)
        var processor = PiAIGoogleFamilyEventProcessor(
            output: PiAIAssistantMessage(
                content: [],
                api: model.api,
                provider: model.provider,
                model: model.id,
                usage: .zero,
                stopReason: .stop,
                timestamp: currentTimestamp()
            ),
            stream: stream
        )

        stream.push(.start(partial: processor.output))
        _ = context // Reserved for future request payload conversion.

        var sawAnyChunk = false
        var attemptIndex = 0
        for chunks in attempts {
            attemptIndex += 1
            if attemptIndex > cappedMaxAttempts { break }
            if chunks.isEmpty {
                continue
            }
            sawAnyChunk = true
            for chunk in chunks {
                try processor.apply(chunk)
            }
            break
        }

        if !sawAnyChunk {
            throw PiAIGoogleFamilySourceError.emptyStreamAfterRetries(cappedMaxAttempts)
        }

        try processor.finish()
        return processor.output
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

private enum PiAIGoogleFamilyProcessorError: Error {
    case unhandledFinishReason(String)
}

private struct PiAIGoogleFamilyEventProcessor {
    var output: PiAIAssistantMessage
    let stream: PiAIAssistantMessageEventStream

    private enum CurrentBlockKind {
        case text(contentIndex: Int)
        case thinking(contentIndex: Int)

        var contentIndex: Int {
            switch self {
            case .text(let contentIndex), .thinking(let contentIndex):
                return contentIndex
            }
        }
    }

    private var currentBlock: CurrentBlockKind?
    private var toolCallCounter = 0

    init(output: PiAIAssistantMessage, stream: PiAIAssistantMessageEventStream) {
        self.output = output
        self.stream = stream
    }

    mutating func apply(_ chunk: PiAIGoogleRawChunk) throws {
        for part in chunk.parts {
            try apply(part)
        }

        if let finishReason = chunk.finishReason {
            output.stopReason = try mapFinishReason(finishReason)
            if output.content.contains(where: { if case .toolCall = $0 { return true } else { return false } }) {
                output.stopReason = .toolUse
            }
        }

        if let usage = chunk.usage {
            output.usage = PiAIUsage(
                input: usage.promptTokenCount,
                output: usage.candidatesTokenCount + usage.thoughtsTokenCount,
                cacheRead: usage.cachedContentTokenCount,
                cacheWrite: 0,
                totalTokens: usage.totalTokenCount,
                cost: .zero
            )
        }
    }

    mutating func finish() throws {
        closeCurrentBlockIfNeeded()

        if output.stopReason == .error || output.stopReason == .aborted {
            throw PiAIGoogleFamilyProcessorError.unhandledFinishReason(output.stopReason.rawValue)
        }

        stream.push(.done(reason: output.stopReason, message: output))
    }

    private mutating func apply(_ part: PiAIGooglePart) throws {
        switch part {
        case .text(let text, let thought, let thoughtSignature):
            let isThinking = PiAIGoogleStreamingSemantics.isThinkingPart(thought: thought, thoughtSignature: thoughtSignature)
            try appendTextPart(text, isThinking: isThinking, thoughtSignature: thoughtSignature)

        case .functionCall(let name, let id, let args, let thoughtSignature):
            closeCurrentBlockIfNeeded()
            let toolCallID = uniqueToolCallID(name: name, preferredID: id)
            let arguments = args ?? [:]
            let toolCall = PiAIToolCallContent(
                id: toolCallID,
                name: name,
                arguments: arguments,
                thoughtSignature: thoughtSignature
            )
            output.content.append(.toolCall(toolCall))
            let contentIndex = output.content.count - 1
            stream.push(.toolCallStart(contentIndex: contentIndex, partial: output))
            stream.push(.toolCallDelta(contentIndex: contentIndex, delta: jsonObjectString(arguments), partial: output))
            stream.push(.toolCallEnd(contentIndex: contentIndex, toolCall: toolCall, partial: output))
        }
    }

    private mutating func appendTextPart(_ text: String, isThinking: Bool, thoughtSignature: String?) throws {
        if isThinking {
            if case .thinking = currentBlock {
                // continue
            } else {
                closeCurrentBlockIfNeeded()
                output.content.append(.thinking(.init(thinking: "", thinkingSignature: nil)))
                let contentIndex = output.content.count - 1
                currentBlock = .thinking(contentIndex: contentIndex)
                stream.push(.thinkingStart(contentIndex: contentIndex, partial: output))
            }

            guard case .thinking(let contentIndex)? = currentBlock else { return }
            guard case .thinking(var block) = output.content[contentIndex] else { return }
            block.thinking += text
            block.thinkingSignature = PiAIGoogleStreamingSemantics.retainThoughtSignature(
                existing: block.thinkingSignature,
                incoming: thoughtSignature
            )
            output.content[contentIndex] = .thinking(block)
            stream.push(.thinkingDelta(contentIndex: contentIndex, delta: text, partial: output))
        } else {
            if case .text = currentBlock {
                // continue
            } else {
                closeCurrentBlockIfNeeded()
                output.content.append(.text(.init(text: "", textSignature: nil)))
                let contentIndex = output.content.count - 1
                currentBlock = .text(contentIndex: contentIndex)
                stream.push(.textStart(contentIndex: contentIndex, partial: output))
            }

            guard case .text(let contentIndex)? = currentBlock else { return }
            guard case .text(var block) = output.content[contentIndex] else { return }
            block.text += text
            block.textSignature = PiAIGoogleStreamingSemantics.retainThoughtSignature(
                existing: block.textSignature,
                incoming: thoughtSignature
            )
            output.content[contentIndex] = .text(block)
            stream.push(.textDelta(contentIndex: contentIndex, delta: text, partial: output))
        }
    }

    private mutating func closeCurrentBlockIfNeeded() {
        guard let currentBlock else { return }
        let contentIndex = currentBlock.contentIndex
        guard output.content.indices.contains(contentIndex) else {
            self.currentBlock = nil
            return
        }

        switch output.content[contentIndex] {
        case .text(let block):
            stream.push(.textEnd(contentIndex: contentIndex, content: block.text, partial: output))
        case .thinking(let block):
            stream.push(.thinkingEnd(contentIndex: contentIndex, content: block.thinking, partial: output))
        case .toolCall:
            break
        }

        self.currentBlock = nil
    }

    private mutating func uniqueToolCallID(name: String, preferredID: String?) -> String {
        let existingIDs = Set(output.content.compactMap { part -> String? in
            if case .toolCall(let toolCall) = part { return toolCall.id }
            return nil
        })

        if let preferredID, !preferredID.isEmpty, !existingIDs.contains(preferredID) {
            return preferredID
        }

        repeat {
            toolCallCounter += 1
            let candidate = "\(name)_\(toolCallCounter)"
            if !existingIDs.contains(candidate) {
                return candidate
            }
        } while true
    }

    private func mapFinishReason(_ reason: PiAIGoogleFinishReason) throws -> PiAIStopReason {
        switch reason {
        case .stop:
            return .stop
        case .maxTokens:
            return .length
        case .safety, .recitation, .blocked:
            return .error
        case .other(let value):
            throw PiAIGoogleFamilyProcessorError.unhandledFinishReason(value)
        }
    }

    private func jsonObjectString(_ object: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(object)),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
}
