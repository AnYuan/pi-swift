import Foundation

public enum PiMomSlackEventType: String, Codable, Equatable, Sendable {
    case mention
    case dm
}

public struct PiMomSlackFileRef: Codable, Equatable, Sendable {
    public var name: String?
    public var urlPrivateDownload: String?
    public var urlPrivate: String?

    public init(name: String? = nil, urlPrivateDownload: String? = nil, urlPrivate: String? = nil) {
        self.name = name
        self.urlPrivateDownload = urlPrivateDownload
        self.urlPrivate = urlPrivate
    }
}

public struct PiMomSlackEvent: Codable, Equatable, Sendable {
    public var type: PiMomSlackEventType
    public var channel: String
    public var ts: String
    public var user: String
    public var text: String
    public var files: [PiMomSlackFileRef]?
    public var attachments: [PiMomAttachment]?

    public init(
        type: PiMomSlackEventType,
        channel: String,
        ts: String,
        user: String,
        text: String,
        files: [PiMomSlackFileRef]? = nil,
        attachments: [PiMomAttachment]? = nil
    ) {
        self.type = type
        self.channel = channel
        self.ts = ts
        self.user = user
        self.text = text
        self.files = files
        self.attachments = attachments
    }
}

public protocol PiMomSlackCommandHandling: Sendable {
    func isRunning(channelID: String) -> Bool
    func handleEvent(_ event: PiMomSlackEvent, isScheduledEvent: Bool)
    func handleStop(channelID: String)
}

public protocol PiMomSlackNotifying: Sendable {
    func postMessage(channelID: String, text: String)
}

public final class PiMomSlackEventDispatcher: @unchecked Sendable {
    private struct QueuedItem: Equatable {
        var event: PiMomSlackEvent
        var isScheduledEvent: Bool
    }

    private let maxQueuedEventsPerChannel: Int
    private var queues: [String: [QueuedItem]] = [:]

    public init(maxQueuedEventsPerChannel: Int = 5) {
        self.maxQueuedEventsPerChannel = max(1, maxQueuedEventsPerChannel)
    }

    @discardableResult
    public func enqueueScheduledEvent(_ event: PiMomSlackEvent) -> Bool {
        enqueue(event, isScheduledEvent: true)
    }

    public func routeIncomingUserEvent(
        _ event: PiMomSlackEvent,
        handler: any PiMomSlackCommandHandling,
        notifier: any PiMomSlackNotifying
    ) {
        if isStopCommand(event.text) {
            if handler.isRunning(channelID: event.channel) {
                handler.handleStop(channelID: event.channel)
            } else {
                notifier.postMessage(channelID: event.channel, text: "_Nothing running_")
            }
            return
        }

        if handler.isRunning(channelID: event.channel) {
            let message = event.type == .mention
                ? "_Already working. Say `@mom stop` to cancel._"
                : "_Already working. Say `stop` to cancel._"
            notifier.postMessage(channelID: event.channel, text: message)
            return
        }

        _ = enqueue(event, isScheduledEvent: false)
    }

    public func queuedCount(channelID: String) -> Int {
        queues[channelID]?.count ?? 0
    }

    public func drainNext(channelID: String, handler: any PiMomSlackCommandHandling) {
        guard var queue = queues[channelID], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        queues[channelID] = queue.isEmpty ? nil : queue
        handler.handleEvent(next.event, isScheduledEvent: next.isScheduledEvent)
    }

    private func enqueue(_ event: PiMomSlackEvent, isScheduledEvent: Bool) -> Bool {
        var queue = queues[event.channel] ?? []
        guard queue.count < maxQueuedEventsPerChannel else { return false }
        queue.append(.init(event: event, isScheduledEvent: isScheduledEvent))
        queues[event.channel] = queue
        return true
    }
}

private func isStopCommand(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop"
}
