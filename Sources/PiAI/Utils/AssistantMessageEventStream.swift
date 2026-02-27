import Foundation

public actor PiAIAssistantMessageEventStream: AsyncSequence {
    public typealias Element = PiAIAssistantMessageEvent

    // The AsyncStream and its continuation are Sendable and thread-safe.
    // They are set once during init and never mutated.
    private let _continuation: AsyncStream<Element>.Continuation
    nonisolated public let _stream: AsyncStream<Element>

    private var finalResultContinuation: CheckedContinuation<PiAIAssistantMessage, Never>?
    private var finalResult: PiAIAssistantMessage?
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

    public func push(_ event: PiAIAssistantMessageEvent) {
        guard !isFinished else { return }
        _continuation.yield(event)

        switch event {
        case .done(_, let message):
            isFinished = true
            finalResult = message
            let waiting = finalResultContinuation
            finalResultContinuation = nil
            _continuation.finish()
            waiting?.resume(returning: message)
        case .error(_, let error):
            isFinished = true
            finalResult = error
            let waiting = finalResultContinuation
            finalResultContinuation = nil
            _continuation.finish()
            waiting?.resume(returning: error)
        default:
            break
        }
    }

    public func end(with result: PiAIAssistantMessage? = nil) {
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

    public func result() async -> PiAIAssistantMessage {
        if let finalResult {
            return finalResult
        }
        return await withCheckedContinuation { continuation in
            finalResultContinuation = continuation
        }
    }
}
