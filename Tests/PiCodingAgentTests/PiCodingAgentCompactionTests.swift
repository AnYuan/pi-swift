import XCTest
import Foundation
import PiAI
import PiAgentCore
import PiCoreTypes
@testable import PiCodingAgent

final class PiCodingAgentCompactionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testShouldCompactTriggersThresholdAndOverflowModes() {
        let state = sampleState(messageCount: 20, textSize: 200)
        let config = PiCodingAgentCompactionConfig(contextWindow: 1_000, reserveTokens: 900, keepRecentMessages: 4, minimumMessagesBeforeCompaction: 5)

        let thresholdDecision = PiCodingAgentCompactionEngine.shouldCompact(state: state, config: config)
        XCTAssertEqual(thresholdDecision.mode, .threshold)
        XCTAssertGreaterThanOrEqual(thresholdDecision.estimatedTokens, thresholdDecision.threshold)

        let overflowDecision = PiCodingAgentCompactionEngine.shouldCompact(
            state: state,
            config: PiCodingAgentCompactionConfig(contextWindow: 999_999, reserveTokens: 0, keepRecentMessages: 4, minimumMessagesBeforeCompaction: 5),
            errorMessage: "Maximum context length exceeded (context overflow)"
        )
        XCTAssertEqual(overflowDecision.mode, .overflow)
    }

    func testApplyCompactionKeepsTailAndInjectsSummaryMessage() {
        let state = sampleState(messageCount: 10, textSize: 20)
        let result = PiCodingAgentCompactionEngine.applyCompaction(
            to: state,
            summaryText: "summary",
            keepRecentMessages: 3,
            timestamp: 123
        )

        XCTAssertEqual(result.firstKeptMessageIndex, 7)
        XCTAssertEqual(result.removedMessages, 7)
        XCTAssertEqual(result.keptMessages, 4) // summary + 3 tail messages
        XCTAssertEqual(result.state.messages.count, 4)
        if case .custom(let message) = result.state.messages[0] {
            XCTAssertEqual(message.role, "compaction_summary")
            XCTAssertEqual(message.timestamp, 123)
            if case .object(let payload) = message.content {
                XCTAssertEqual(payload["type"], .string("compaction_summary"))
                XCTAssertEqual(payload["text"], .string("summary"))
            } else {
                XCTFail("Expected compaction summary object payload")
            }
        } else {
            XCTFail("First message should be compaction summary")
        }
    }

    func testCompactionLogStoreAppendAndLatest() throws {
        let clock = FixedCompactionClock([date(1000), date(2000)])
        let store = PiCodingAgentCompactionLogStore(
            directory: tempDir.appendingPathComponent("compactions").path,
            clock: { clock.next() },
            idGenerator: { "entry-\(Int(clock.next().timeIntervalSince1970))" }
        )

        let first = try store.append(
            sessionID: "s1",
            mode: .threshold,
            estimatedTokensBefore: 100,
            threshold: 90,
            removedMessages: 10,
            keptMessages: 5,
            firstKeptMessageIndex: 10,
            summaryText: "a"
        )
        let second = try store.append(
            sessionID: "s1",
            mode: .overflow,
            estimatedTokensBefore: 200,
            threshold: 90,
            removedMessages: 20,
            keptMessages: 5,
            firstKeptMessageIndex: 20,
            summaryText: "b"
        )

        let entries = try store.list(sessionID: "s1")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last, second)
        XCTAssertEqual(try store.latest(sessionID: "s1"), second)
        XCTAssertEqual(first.mode, .threshold)
    }

    func testAutoCompactionQueueQueuesDuringCompactionAndFlushesInOrder() {
        let queue = PiCodingAgentAutoCompactionQueue()
        var dispatched: [PiCodingAgentAutoCompactionQueue.QueuedMessage] = []

        queue.beginCompaction()
        XCTAssertTrue(queue.enqueueOrDispatch(.init(text: "a"), dispatch: { dispatched.append($0) }))
        XCTAssertTrue(queue.enqueueOrDispatch(.init(text: "b", mode: "retry"), dispatch: { dispatched.append($0) }))
        XCTAssertTrue(dispatched.isEmpty)
        XCTAssertEqual(queue.queuedMessages().map(\.text), ["a", "b"])

        queue.flush { dispatched.append($0) } // should not flush while compacting
        XCTAssertTrue(dispatched.isEmpty)

        queue.endCompaction()
        queue.flush { dispatched.append($0) }
        XCTAssertEqual(dispatched.map(\.text), ["a", "b"])
        XCTAssertEqual(queue.queuedMessages(), [])
    }

    func testCoordinatorAutoCompactsAndPersistsUpdatedSessionAndLog() throws {
        let sessionClock = FixedCompactionClock([date(1000), date(2000)])
        let sessionStore = PiCodingAgentSessionStore(
            directory: tempDir.appendingPathComponent("sessions").path,
            clock: { sessionClock.next() },
            idGenerator: { "session-1" }
        )
        let original = try sessionStore.saveNew(state: sampleState(messageCount: 15, textSize: 120), title: "Chat")

        let logClock = FixedCompactionClock([date(3000)])
        let logStore = PiCodingAgentCompactionLogStore(
            directory: tempDir.appendingPathComponent("compactions").path,
            clock: { logClock.next() },
            idGenerator: { "cmp-1" }
        )
        let queue = PiCodingAgentAutoCompactionQueue()
        let coordinator = PiCodingAgentCompactionCoordinator(
            sessionStore: sessionStore,
            compactionLogStore: logStore,
            timestampProvider: { 999 }
        )

        // begin manually so message is queued and later flushed after compaction
        queue.beginCompaction()
        _ = queue.enqueueOrDispatch(.init(text: "queued"), dispatch: { _ in XCTFail("Should queue") })
        queue.endCompaction()

        let entry = try coordinator.maybeAutoCompact(
            sessionID: original.id,
            config: .init(contextWindow: 1_000, reserveTokens: 950, keepRecentMessages: 4, minimumMessagesBeforeCompaction: 5),
            queue: queue
        ) { _, mode in
            "summary-\(mode.rawValue)"
        }

        let saved = try sessionStore.load(id: original.id)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.id, "cmp-1")
        XCTAssertEqual(entry?.mode, .threshold)
        XCTAssertTrue(saved.state.messages.count <= 5)
        if case .custom = saved.state.messages.first {
        } else {
            XCTFail("Compacted session should start with summary message")
        }

        var flushed: [String] = []
        queue.flush { flushed.append($0.text) }
        XCTAssertEqual(flushed, ["queued"])
    }

    private func sampleState(messageCount: Int, textSize: Int) -> PiAgentState {
        var state = PiAgentState.empty(model: .init(provider: "openai", id: "gpt-5"), systemPrompt: "system prompt")
        let chunk = String(repeating: "x", count: textSize)
        state.messages = (0..<messageCount).map { idx in
            .user(.init(content: .text("msg-\(idx)-\(chunk)"), timestamp: Int64(idx)))
        }
        return state
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

private final class FixedCompactionClock: @unchecked Sendable {
    private var dates: [Date]
    private var index = 0

    init(_ dates: [Date]) { self.dates = dates }

    func next() -> Date {
        guard !dates.isEmpty else { return Date(timeIntervalSince1970: 0) }
        let date = dates[min(index, dates.count - 1)]
        index += 1
        return date
    }
}
