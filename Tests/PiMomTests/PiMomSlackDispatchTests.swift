import XCTest
@testable import PiMom

final class PiMomSlackDispatchTests: XCTestCase {
    func testStopCommandWhenRunningInvokesHandlerImmediatelyWithoutQueueing() {
        let dispatcher = PiMomSlackEventDispatcher()
        let handler = RecordingSlackHandler(runningChannels: ["C1"])
        let notifier = RecordingSlackNotifier()

        dispatcher.routeIncomingUserEvent(
            .init(type: .mention, channel: "C1", ts: "1", user: "U1", text: "stop"),
            handler: handler,
            notifier: notifier
        )

        XCTAssertEqual(handler.stopCalls, ["C1"])
        XCTAssertTrue(handler.handledEvents.isEmpty)
        XCTAssertEqual(dispatcher.queuedCount(channelID: "C1"), 0)
        XCTAssertTrue(notifier.messages.isEmpty)
    }

    func testStopCommandWhenIdlePostsNothingRunningMessage() {
        let dispatcher = PiMomSlackEventDispatcher()
        let handler = RecordingSlackHandler(runningChannels: [])
        let notifier = RecordingSlackNotifier()

        dispatcher.routeIncomingUserEvent(
            .init(type: .dm, channel: "D1", ts: "1", user: "U1", text: "stop"),
            handler: handler,
            notifier: notifier
        )

        XCTAssertEqual(notifier.messages.map(\.joined), ["D1::_Nothing running_"])
        XCTAssertTrue(handler.stopCalls.isEmpty)
        XCTAssertEqual(dispatcher.queuedCount(channelID: "D1"), 0)
    }

    func testBusyMentionAndDMBothPostCorrectMessages() {
        let dispatcher = PiMomSlackEventDispatcher()
        let handler = RecordingSlackHandler(runningChannels: ["C1", "D1"])
        let notifier = RecordingSlackNotifier()

        dispatcher.routeIncomingUserEvent(.init(type: .mention, channel: "C1", ts: "1", user: "U", text: "build"), handler: handler, notifier: notifier)
        dispatcher.routeIncomingUserEvent(.init(type: .dm, channel: "D1", ts: "2", user: "U", text: "build"), handler: handler, notifier: notifier)

        XCTAssertEqual(notifier.messages.map(\.joined), [
            "C1::_Already working. Say `@mom stop` to cancel._",
            "D1::_Already working. Say `stop` to cancel._"
        ])
        XCTAssertTrue(handler.handledEvents.isEmpty)
    }

    func testIdleUserMessageQueuesThenDrainsToHandler() {
        let dispatcher = PiMomSlackEventDispatcher()
        let handler = RecordingSlackHandler(runningChannels: [])
        let notifier = RecordingSlackNotifier()
        let event = PiMomSlackEvent(type: .mention, channel: "C1", ts: "1", user: "U1", text: "hello")

        dispatcher.routeIncomingUserEvent(event, handler: handler, notifier: notifier)
        XCTAssertEqual(dispatcher.queuedCount(channelID: "C1"), 1)
        XCTAssertTrue(handler.handledEvents.isEmpty)

        dispatcher.drainNext(channelID: "C1", handler: handler)

        XCTAssertEqual(dispatcher.queuedCount(channelID: "C1"), 0)
        XCTAssertEqual(handler.handledEvents.count, 1)
        XCTAssertEqual(handler.handledEvents[0].event, event)
        XCTAssertEqual(handler.handledEvents[0].isScheduledEvent, false)
    }

    func testScheduledEventsAlwaysQueueAndHonorMaxQueueSize() {
        let dispatcher = PiMomSlackEventDispatcher()
        let handler = RecordingSlackHandler(runningChannels: [])

        for index in 0..<5 {
            let accepted = dispatcher.enqueueScheduledEvent(.init(type: .dm, channel: "C1", ts: "\(index)", user: "U", text: "evt-\(index)"))
            XCTAssertTrue(accepted)
        }
        XCTAssertFalse(dispatcher.enqueueScheduledEvent(.init(type: .dm, channel: "C1", ts: "x", user: "U", text: "overflow")))
        XCTAssertEqual(dispatcher.queuedCount(channelID: "C1"), 5)

        for _ in 0..<5 {
            dispatcher.drainNext(channelID: "C1", handler: handler)
        }

        XCTAssertEqual(handler.handledEvents.map(\.event.text), ["evt-0", "evt-1", "evt-2", "evt-3", "evt-4"])
        XCTAssertTrue(handler.handledEvents.allSatisfy(\.isScheduledEvent))
    }
}

private final class RecordingSlackHandler: PiMomSlackCommandHandling, @unchecked Sendable {
    struct Handled: Equatable {
        var event: PiMomSlackEvent
        var isScheduledEvent: Bool
    }

    private let runningSet: Set<String>
    private(set) var handledEvents: [Handled] = []
    private(set) var stopCalls: [String] = []

    init(runningChannels: Set<String>) {
        self.runningSet = runningChannels
    }

    func isRunning(channelID: String) -> Bool {
        runningSet.contains(channelID)
    }

    func handleEvent(_ event: PiMomSlackEvent, isScheduledEvent: Bool) {
        handledEvents.append(.init(event: event, isScheduledEvent: isScheduledEvent))
    }

    func handleStop(channelID: String) {
        stopCalls.append(channelID)
    }
}

private final class RecordingSlackNotifier: PiMomSlackNotifying, @unchecked Sendable {
    struct Message: Equatable {
        var channelID: String
        var text: String
        var joined: String { "\(channelID)::\(text)" }
    }

    private(set) var messages: [Message] = []

    func postMessage(channelID: String, text: String) {
        messages.append(.init(channelID: channelID, text: text))
    }
}
