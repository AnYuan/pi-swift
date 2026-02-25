import XCTest
import Foundation
@testable import PiMom
@testable import PiAgentCore
@testable import PiAI

final class PiMomCoordinatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-mom-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testReceiveUserEventLogsMessageSyncsContextAndRunsCoordinatorFlow() throws {
        let scheduler = ManualScheduler()
        let slack = RecordingSlackClient()
        let runnerFactory = RecordingRunnerFactory { run in
            run.observedContextUserTexts = (try? run.contextStore.loadMessages(channelID: run.event.channel).compactMap { userText($0) }) ?? []
            run.context.respond("Done")
            return .init(stopReason: .stop)
        }

        // Offline message already logged before current run.
        let seedStore = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: NoopDownloader())
        _ = try seedStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T09:00:00Z",
            ts: "100.0",
            user: "U0",
            userName: "offline",
            text: "missed while offline",
            attachments: [],
            isBot: false
        ))

        let coordinator = PiMomRunCoordinator(
            workingDirectory: tempDir.path,
            slackClient: slack,
            runnerFactory: runnerFactory.makeRunner(channelID:channelDirectory:)
        )
        coordinator.executionScheduler = scheduler

        coordinator.receiveUserEvent(.init(type: .mention, channel: "C1", ts: "101.0", user: "U1", text: "hello"))

        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(runnerFactory.created.count, 1)

        // Current message should be logged before run starts.
        let preRunLog = try String(contentsOf: tempDir.appendingPathComponent("C1/log.jsonl"), encoding: .utf8)
        XCTAssertTrue(preRunLog.contains("\"text\":\"hello\""))

        scheduler.runNext()

        XCTAssertEqual(runnerFactory.runs.count, 1)
        XCTAssertEqual(runnerFactory.runs[0].event.text, "hello")
        XCTAssertFalse(runnerFactory.runs[0].isScheduledEvent)
        XCTAssertEqual(runnerFactory.runs[0].observedContextUserTexts, ["[offline]: missed while offline"])

        XCTAssertTrue(slack.posts.contains(where: { $0.text.contains("_Thinking_") }))
        XCTAssertTrue(slack.updates.contains(where: { $0.text.contains("Done") }))

        let postRunLog = try String(contentsOf: tempDir.appendingPathComponent("C1/log.jsonl"), encoding: .utf8)
        XCTAssertTrue(postRunLog.contains("\"text\":\"Done\""))
        XCTAssertTrue(postRunLog.contains("\"isBot\":true"))
    }

    func testStopWhileRunningAbortsRunnerAndUpdatesStoppedMessageAfterAbortedRun() throws {
        let scheduler = ManualScheduler()
        let slack = RecordingSlackClient()
        let runnerFactory = RecordingRunnerFactory { _ in .init(stopReason: .aborted) }
        let coordinator = PiMomRunCoordinator(
            workingDirectory: tempDir.path,
            slackClient: slack,
            runnerFactory: runnerFactory.makeRunner(channelID:channelDirectory:)
        )
        coordinator.executionScheduler = scheduler

        coordinator.receiveUserEvent(.init(type: .mention, channel: "C1", ts: "1", user: "U1", text: "work"))
        XCTAssertEqual(scheduler.pendingCount, 1)

        coordinator.receiveUserEvent(.init(type: .mention, channel: "C1", ts: "2", user: "U1", text: "stop"))

        XCTAssertEqual(runnerFactory.created.first?.abortCalls, 1)
        XCTAssertTrue(slack.posts.contains(where: { $0.text == "_Stopping..._" }))

        scheduler.runNext()

        XCTAssertTrue(slack.updates.contains(where: { $0.text == "_Stopped_" }))
    }

    func testScheduledEventQueuedDuringRunExecutesAfterCurrentRunFinishes() throws {
        let scheduler = ManualScheduler()
        let slack = RecordingSlackClient()
        let runnerFactory = RecordingRunnerFactory { run in
            run.context.respond(run.isScheduledEvent ? "scheduled" : "primary")
            return .init(stopReason: .stop)
        }
        let coordinator = PiMomRunCoordinator(
            workingDirectory: tempDir.path,
            slackClient: slack,
            runnerFactory: runnerFactory.makeRunner(channelID:channelDirectory:)
        )
        coordinator.executionScheduler = scheduler

        coordinator.receiveUserEvent(.init(type: .dm, channel: "D1", ts: "1", user: "U1", text: "first"))
        XCTAssertEqual(scheduler.pendingCount, 1)

        let accepted = coordinator.enqueueScheduledEvent(.init(type: .dm, channel: "D1", ts: "evt", user: "system", text: "[EVENT:test] ping"))
        XCTAssertTrue(accepted)
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.runNext()
        XCTAssertEqual(scheduler.pendingCount, 1)
        scheduler.runNext()

        XCTAssertEqual(runnerFactory.runs.map(\.event.text), ["first", "[EVENT:test] ping"])
        XCTAssertEqual(runnerFactory.runs.map(\.isScheduledEvent), [false, true])
    }
}

private final class RecordingRunnerFactory: @unchecked Sendable {
    typealias Behavior = (RecordingRunnerFactory.RunRecord) -> PiMomRunResult

    final class Runner: PiMomRunner, @unchecked Sendable {
        let channelID: String
        let channelDirectory: String
        let parent: RecordingRunnerFactory
        private let behavior: Behavior
        private(set) var abortCalls = 0

        init(channelID: String, channelDirectory: String, parent: RecordingRunnerFactory, behavior: @escaping Behavior) {
            self.channelID = channelID
            self.channelDirectory = channelDirectory
            self.parent = parent
            self.behavior = behavior
        }

        func run(
            event: PiMomSlackEvent,
            context: PiMomSlackRunContext,
            store: PiMomChannelStore,
            contextStore: PiMomContextStore,
            isScheduledEvent: Bool
        ) -> PiMomRunResult {
            let record = RunRecord(
                runner: self,
                event: event,
                context: context,
                store: store,
                contextStore: contextStore,
                isScheduledEvent: isScheduledEvent
            )
            parent.runs.append(record)
            return behavior(record)
        }

        func abort() {
            abortCalls += 1
        }
    }

    final class RunRecord: @unchecked Sendable {
        let runner: Runner
        let event: PiMomSlackEvent
        let context: PiMomSlackRunContext
        let store: PiMomChannelStore
        let contextStore: PiMomContextStore
        let isScheduledEvent: Bool
        var observedContextUserTexts: [String] = []

        init(
            runner: Runner,
            event: PiMomSlackEvent,
            context: PiMomSlackRunContext,
            store: PiMomChannelStore,
            contextStore: PiMomContextStore,
            isScheduledEvent: Bool
        ) {
            self.runner = runner
            self.event = event
            self.context = context
            self.store = store
            self.contextStore = contextStore
            self.isScheduledEvent = isScheduledEvent
        }
    }

    private let behavior: Behavior
    private(set) var created: [Runner] = []
    private(set) var runs: [RunRecord] = []

    init(behavior: @escaping Behavior) {
        self.behavior = behavior
    }

    func makeRunner(channelID: String, channelDirectory: String) -> any PiMomRunner {
        let runner = Runner(channelID: channelID, channelDirectory: channelDirectory, parent: self, behavior: behavior)
        created.append(runner)
        return runner
    }
}

private final class RecordingSlackClient: PiMomSlackClient, @unchecked Sendable {
    struct Post: Equatable { var channelID: String; var text: String; var ts: String }
    struct Update: Equatable { var channelID: String; var ts: String; var text: String }
    struct ThreadPost: Equatable { var channelID: String; var threadTS: String; var text: String; var ts: String }
    struct Upload: Equatable { var channelID: String; var filePath: String; var title: String? }
    struct Delete: Equatable { var channelID: String; var ts: String }

    private var nextTS = 1
    private(set) var posts: [Post] = []
    private(set) var updates: [Update] = []
    private(set) var threadPosts: [ThreadPost] = []
    private(set) var uploads: [Upload] = []
    private(set) var deletes: [Delete] = []

    func postMessageWithTS(channelID: String, text: String) -> String {
        let ts = "\(nextTS)"
        nextTS += 1
        posts.append(.init(channelID: channelID, text: text, ts: ts))
        return ts
    }

    func updateMessage(channelID: String, ts: String, text: String) {
        updates.append(.init(channelID: channelID, ts: ts, text: text))
    }

    func deleteMessage(channelID: String, ts: String) {
        deletes.append(.init(channelID: channelID, ts: ts))
    }

    func postInThread(channelID: String, threadTS: String, text: String) -> String {
        let ts = "\(nextTS)"
        nextTS += 1
        threadPosts.append(.init(channelID: channelID, threadTS: threadTS, text: text, ts: ts))
        return ts
    }

    func uploadFile(channelID: String, filePath: String, title: String?) {
        uploads.append(.init(channelID: channelID, filePath: filePath, title: title))
    }
}

private final class ManualScheduler: PiMomWorkScheduling, @unchecked Sendable {
    private var queue: [() -> Void] = []

    var pendingCount: Int { queue.count }

    func schedule(_ work: @escaping @Sendable () -> Void) {
        queue.append(work)
    }

    func runNext() {
        guard !queue.isEmpty else { return }
        let work = queue.removeFirst()
        work()
    }
}

private final class NoopDownloader: PiMomAttachmentDownloading, @unchecked Sendable {
    func download(url: String, authToken: String?) throws -> Data {
        _ = url
        _ = authToken
        return Data()
    }
}

private func userText(_ message: PiAgentMessage) -> String? {
    guard case .user(let user) = message else { return nil }
    switch user.content {
    case .text(let text):
        return text
    case .parts(let parts):
        for part in parts {
            if case .text(let value) = part { return value.text }
        }
        return nil
    }
}
