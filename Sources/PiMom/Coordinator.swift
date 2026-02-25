import Foundation

public protocol PiMomSlackClient: PiMomSlackNotifying, Sendable {
    func postMessageWithTS(channelID: String, text: String) -> String
    func updateMessage(channelID: String, ts: String, text: String)
    func deleteMessage(channelID: String, ts: String)
    func postInThread(channelID: String, threadTS: String, text: String) -> String
    func uploadFile(channelID: String, filePath: String, title: String?)
}

public extension PiMomSlackClient {
    func postMessage(channelID: String, text: String) {
        _ = postMessageWithTS(channelID: channelID, text: text)
    }
}

public protocol PiMomWorkScheduling: Sendable {
    func schedule(_ work: @escaping @Sendable () -> Void)
}

public final class PiMomDispatchQueueScheduler: PiMomWorkScheduling, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(label: String = "PiMomRunCoordinator") {
        self.queue = DispatchQueue(label: label)
    }

    public func schedule(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}

public enum PiMomRunStopReason: String, Codable, Equatable, Sendable {
    case stop
    case aborted
    case error
}

public struct PiMomRunResult: Codable, Equatable, Sendable {
    public var stopReason: PiMomRunStopReason
    public var errorMessage: String?

    public init(stopReason: PiMomRunStopReason, errorMessage: String? = nil) {
        self.stopReason = stopReason
        self.errorMessage = errorMessage
    }
}

public protocol PiMomRunner: AnyObject, Sendable {
    func run(
        event: PiMomSlackEvent,
        context: PiMomSlackRunContext,
        store: PiMomChannelStore,
        contextStore: PiMomContextStore,
        isScheduledEvent: Bool
    ) -> PiMomRunResult
    func abort()
}

public final class PiMomSlackRunContext: @unchecked Sendable {
    public struct Message: Equatable, Sendable {
        public var text: String
        public var user: String
        public var channel: String
        public var ts: String
        public var attachments: [PiMomAttachment]

        public init(text: String, user: String, channel: String, ts: String, attachments: [PiMomAttachment]) {
            self.text = text
            self.user = user
            self.channel = channel
            self.ts = ts
            self.attachments = attachments
        }
    }

    public let message: Message
    public let channelName: String?

    private let slack: any PiMomSlackClient
    private let store: PiMomChannelStore
    private let lock = NSLock()

    private var messageTS: String?
    private var threadMessageTS: [String] = []
    private var accumulatedText = ""
    private var isWorking = true

    public init(
        event: PiMomSlackEvent,
        slack: any PiMomSlackClient,
        store: PiMomChannelStore,
        channelName: String? = nil
    ) {
        self.message = .init(
            text: event.text,
            user: event.user,
            channel: event.channel,
            ts: event.ts,
            attachments: event.attachments ?? []
        )
        self.channelName = channelName
        self.slack = slack
        self.store = store
    }

    public func respond(_ text: String, shouldLog: Bool = true) {
        lock.lock()
        defer { lock.unlock() }

        accumulatedText = accumulatedText.isEmpty ? text : accumulatedText + "\n" + text
        let displayText = isWorking ? accumulatedText + " ..." : accumulatedText
        if let messageTS {
            slack.updateMessage(channelID: message.channel, ts: messageTS, text: displayText)
        } else {
            self.messageTS = slack.postMessageWithTS(channelID: message.channel, text: displayText)
        }
        if shouldLog, let currentTS = self.messageTS {
            try? store.logBotResponse(channelID: message.channel, text: text, ts: currentTS)
        }
    }

    public func replaceMessage(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        accumulatedText = text
        let displayText = isWorking ? accumulatedText + " ..." : accumulatedText
        if let messageTS {
            slack.updateMessage(channelID: message.channel, ts: messageTS, text: displayText)
        } else {
            self.messageTS = slack.postMessageWithTS(channelID: message.channel, text: displayText)
        }
    }

    public func respondInThread(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let messageTS else { return }
        let ts = slack.postInThread(channelID: message.channel, threadTS: messageTS, text: text)
        threadMessageTS.append(ts)
    }

    public func setTyping(_ isTyping: Bool) {
        guard isTyping else { return }
        lock.lock()
        defer { lock.unlock() }

        guard messageTS == nil else { return }
        accumulatedText = "_Thinking_"
        self.messageTS = slack.postMessageWithTS(channelID: message.channel, text: accumulatedText + " ...")
    }

    public func uploadFile(_ filePath: String, title: String? = nil) {
        slack.uploadFile(channelID: message.channel, filePath: filePath, title: title)
    }

    public func setWorking(_ working: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isWorking = working
        guard let messageTS else { return }
        let displayText = isWorking ? accumulatedText + " ..." : accumulatedText
        slack.updateMessage(channelID: message.channel, ts: messageTS, text: displayText)
    }

    public func deleteMessage() {
        lock.lock()
        defer { lock.unlock() }
        for ts in threadMessageTS.reversed() {
            slack.deleteMessage(channelID: message.channel, ts: ts)
        }
        threadMessageTS.removeAll()
        if let messageTS {
            slack.deleteMessage(channelID: message.channel, ts: messageTS)
            self.messageTS = nil
        }
    }
}

public final class PiMomRunCoordinator: PiMomSlackCommandHandling, @unchecked Sendable {
    public typealias RunnerFactory = @Sendable (_ channelID: String, _ channelDirectory: String) -> any PiMomRunner

    private struct ChannelState {
        var running: Bool
        var runner: any PiMomRunner
        var stopRequested: Bool
        var stopMessageTS: String?
    }

    public var executionScheduler: any PiMomWorkScheduling {
        didSet {
            // runtime-configurable for tests; no-op hook
        }
    }

    private let workingDirectory: String
    private let slackClient: any PiMomSlackClient
    private let dispatcher: PiMomSlackEventDispatcher
    private let runnerFactory: RunnerFactory
    private let channelStore: PiMomChannelStore
    private let contextStore: PiMomContextStore
    private let lock = NSLock()
    private var states: [String: ChannelState] = [:]

    public init(
        workingDirectory: String,
        slackClient: any PiMomSlackClient,
        dispatcher: PiMomSlackEventDispatcher = .init(),
        channelStore: PiMomChannelStore? = nil,
        contextStore: PiMomContextStore? = nil,
        runnerFactory: @escaping RunnerFactory,
        executionScheduler: (any PiMomWorkScheduling)? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.slackClient = slackClient
        self.dispatcher = dispatcher
        self.channelStore = channelStore ?? PiMomChannelStore(workingDirectory: workingDirectory)
        self.contextStore = contextStore ?? PiMomContextStore(workingDirectory: workingDirectory)
        self.runnerFactory = runnerFactory
        self.executionScheduler = executionScheduler ?? PiMomDispatchQueueScheduler()
    }

    public func receiveUserEvent(_ event: PiMomSlackEvent) {
        let processed = preprocessIncomingEvent(event)
        dispatcher.routeIncomingUserEvent(processed, handler: self, notifier: slackClient)
        if !isRunning(channelID: processed.channel) {
            dispatcher.drainNext(channelID: processed.channel, handler: self)
        }
    }

    @discardableResult
    public func enqueueScheduledEvent(_ event: PiMomSlackEvent) -> Bool {
        let accepted = dispatcher.enqueueScheduledEvent(event)
        if accepted, !isRunning(channelID: event.channel) {
            dispatcher.drainNext(channelID: event.channel, handler: self)
        }
        return accepted
    }

    public func isRunning(channelID: String) -> Bool {
        lock.lock()
        let running = states[channelID]?.running ?? false
        lock.unlock()
        return running
    }

    public func handleEvent(_ event: PiMomSlackEvent, isScheduledEvent: Bool) {
        let state = getOrCreateState(channelID: event.channel)
        lock.lock()
        if var stored = states[event.channel] {
            stored.running = true
            stored.stopRequested = false
            stored.stopMessageTS = nil
            states[event.channel] = stored
        }
        lock.unlock()

        executionScheduler.schedule { [self] in
            runEvent(event, isScheduledEvent: isScheduledEvent, runner: state.runner)
        }
    }

    public func handleStop(channelID: String) {
        let runner: (any PiMomRunner)?
        lock.lock()
        if var state = states[channelID], state.running {
            state.stopRequested = true
            states[channelID] = state
            runner = state.runner
        } else {
            runner = nil
        }
        lock.unlock()

        guard let runner else {
            slackClient.postMessage(channelID: channelID, text: "_Nothing running_")
            return
        }

        runner.abort()
        let ts = slackClient.postMessageWithTS(channelID: channelID, text: "_Stopping..._")

        lock.lock()
        if var state = states[channelID] {
            state.stopMessageTS = ts
            states[channelID] = state
        }
        lock.unlock()
    }

    private func runEvent(_ event: PiMomSlackEvent, isScheduledEvent: Bool, runner: any PiMomRunner) {
        let context = PiMomSlackRunContext(event: event, slack: slackClient, store: channelStore)
        _ = try? contextStore.syncLogToContext(channelID: event.channel, excludeSlackTimestamp: event.ts)

        context.setTyping(true)
        context.setWorking(true)
        let result = runner.run(
            event: event,
            context: context,
            store: channelStore,
            contextStore: contextStore,
            isScheduledEvent: isScheduledEvent
        )
        context.setWorking(false)

        var stoppedTS: String?
        var shouldPostStopped = false

        lock.lock()
        if var state = states[event.channel] {
            if result.stopReason == .aborted && state.stopRequested {
                stoppedTS = state.stopMessageTS
                shouldPostStopped = true
            }
            state.running = false
            state.stopRequested = false
            state.stopMessageTS = nil
            states[event.channel] = state
        }
        lock.unlock()

        if shouldPostStopped {
            if let stoppedTS {
                slackClient.updateMessage(channelID: event.channel, ts: stoppedTS, text: "_Stopped_")
            } else {
                _ = slackClient.postMessageWithTS(channelID: event.channel, text: "_Stopped_")
            }
        }

        dispatcher.drainNext(channelID: event.channel, handler: self)
    }

    private func preprocessIncomingEvent(_ event: PiMomSlackEvent) -> PiMomSlackEvent {
        var event = event
        if let files = event.files, !files.isEmpty {
            let attachments = channelStore.processAttachments(channelID: event.channel, files: files, timestamp: event.ts)
            event.attachments = attachments
            channelStore.processPendingDownloads()
        }
        _ = try? channelStore.logMessage(channelID: event.channel, message: .init(
            ts: event.ts,
            user: event.user,
            text: event.text,
            attachments: event.attachments ?? [],
            isBot: false
        ))
        return event
    }

    private func getOrCreateState(channelID: String) -> ChannelState {
        lock.lock()
        defer { lock.unlock() }
        if let state = states[channelID] { return state }
        let channelDirectory = (workingDirectory as NSString).appendingPathComponent(channelID)
        let runner = runnerFactory(channelID, channelDirectory)
        let state = ChannelState(running: false, runner: runner, stopRequested: false, stopMessageTS: nil)
        states[channelID] = state
        return state
    }
}
