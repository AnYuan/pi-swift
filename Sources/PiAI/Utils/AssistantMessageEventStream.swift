import Foundation

public final class PiAIAssistantMessageEventStream: AsyncSequence, @unchecked Sendable {
    public typealias Element = PiAIAssistantMessageEvent

    private final class ContinuationBox {
        var continuation: AsyncStream<Element>.Continuation?
    }

    private let lock = NSLock()
    private let continuationBox: ContinuationBox
    private let stream: AsyncStream<Element>
    private var finalResultContinuation: CheckedContinuation<PiAIAssistantMessage, Never>?
    private var finalResult: PiAIAssistantMessage?
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

    public func push(_ event: PiAIAssistantMessageEvent) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        continuationBox.continuation?.yield(event)

        switch event {
        case .done(_, let message):
            isFinished = true
            finalResult = message
            let finalResultContinuation = self.finalResultContinuation
            self.finalResultContinuation = nil
            continuationBox.continuation?.finish()
            lock.unlock()
            finalResultContinuation?.resume(returning: message)
            return
        case .error(_, let error):
            isFinished = true
            finalResult = error
            let finalResultContinuation = self.finalResultContinuation
            self.finalResultContinuation = nil
            continuationBox.continuation?.finish()
            lock.unlock()
            finalResultContinuation?.resume(returning: error)
            return
        default:
            lock.unlock()
        }
    }

    public func end(with result: PiAIAssistantMessage? = nil) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        if let result {
            finalResult = result
        }
        let finalResultContinuation = self.finalResultContinuation
        self.finalResultContinuation = nil
        continuationBox.continuation?.finish()
        let final = finalResult
        lock.unlock()
        if let final {
            finalResultContinuation?.resume(returning: final)
        }
    }

    public func result() async -> PiAIAssistantMessage {
        return await withCheckedContinuation { continuation in
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
