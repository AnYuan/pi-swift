import Foundation
import PiAgentCore
import PiAI
import PiCoreTypes

public enum PiCodingAgentCompactionMode: String, Codable, Equatable, Sendable {
    case manual
    case threshold
    case overflow
}

public struct PiCodingAgentCompactionConfig: Equatable, Sendable {
    public var contextWindow: Int
    public var reserveTokens: Int
    public var keepRecentMessages: Int
    public var minimumMessagesBeforeCompaction: Int

    public init(
        contextWindow: Int,
        reserveTokens: Int = 4_000,
        keepRecentMessages: Int = 8,
        minimumMessagesBeforeCompaction: Int = 12
    ) {
        self.contextWindow = max(1, contextWindow)
        self.reserveTokens = max(0, reserveTokens)
        self.keepRecentMessages = max(1, keepRecentMessages)
        self.minimumMessagesBeforeCompaction = max(1, minimumMessagesBeforeCompaction)
    }
}

public struct PiCodingAgentCompactionDecision: Equatable, Sendable {
    public var mode: PiCodingAgentCompactionMode?
    public var estimatedTokens: Int
    public var threshold: Int

    public init(mode: PiCodingAgentCompactionMode?, estimatedTokens: Int, threshold: Int) {
        self.mode = mode
        self.estimatedTokens = estimatedTokens
        self.threshold = threshold
    }
}

public struct PiCodingAgentCompactionApplyResult: Equatable, Sendable {
    public var state: PiAgentState
    public var firstKeptMessageIndex: Int
    public var removedMessages: Int
    public var keptMessages: Int
}

public struct PiCodingAgentCompactionEntry: Codable, Equatable, Sendable {
    public var id: String
    public var sessionID: String
    public var mode: PiCodingAgentCompactionMode
    public var createdAt: Date
    public var estimatedTokensBefore: Int
    public var threshold: Int
    public var removedMessages: Int
    public var keptMessages: Int
    public var firstKeptMessageIndex: Int
    public var summaryText: String

    public init(
        id: String,
        sessionID: String,
        mode: PiCodingAgentCompactionMode,
        createdAt: Date,
        estimatedTokensBefore: Int,
        threshold: Int,
        removedMessages: Int,
        keptMessages: Int,
        firstKeptMessageIndex: Int,
        summaryText: String
    ) {
        self.id = id
        self.sessionID = sessionID
        self.mode = mode
        self.createdAt = createdAt
        self.estimatedTokensBefore = estimatedTokensBefore
        self.threshold = threshold
        self.removedMessages = removedMessages
        self.keptMessages = keptMessages
        self.firstKeptMessageIndex = firstKeptMessageIndex
        self.summaryText = summaryText
    }
}

public enum PiCodingAgentCompactionError: Error, Equatable, CustomStringConvertible {
    case notNeeded
    case io(String)
    case sessionStore(String)

    public var description: String {
        switch self {
        case .notNeeded:
            return "Compaction not needed"
        case .io(let message):
            return "Compaction I/O error: \(message)"
        case .sessionStore(let message):
            return "Compaction session error: \(message)"
        }
    }
}

public enum PiCodingAgentCompactionEngine {
    public static func estimateContextTokens(systemPrompt: String, messages: [PiAgentMessage]) -> Int {
        var total = tokenEstimate(for: systemPrompt)
        for message in messages {
            total += 8 // role/metadata overhead
            total += tokenEstimate(for: flatten(message))
        }
        return total
    }

    public static func shouldCompact(
        state: PiAgentState,
        config: PiCodingAgentCompactionConfig,
        errorMessage: String? = nil
    ) -> PiCodingAgentCompactionDecision {
        let estimated = estimateContextTokens(systemPrompt: state.systemPrompt, messages: state.messages)
        let threshold = max(1, config.contextWindow - config.reserveTokens)
        let hasOverflowSignal = errorMessage.map(isContextOverflowSignal) ?? false

        let mode: PiCodingAgentCompactionMode?
        if hasOverflowSignal, state.messages.count >= config.minimumMessagesBeforeCompaction {
            mode = .overflow
        } else if estimated >= threshold, state.messages.count >= config.minimumMessagesBeforeCompaction {
            mode = .threshold
        } else {
            mode = nil
        }

        return .init(mode: mode, estimatedTokens: estimated, threshold: threshold)
    }

    public static func applyCompaction(
        to state: PiAgentState,
        summaryText: String,
        keepRecentMessages: Int,
        timestamp: Int64
    ) -> PiCodingAgentCompactionApplyResult {
        let keep = max(1, keepRecentMessages)
        let firstKeptIndex = max(0, state.messages.count - keep)
        let tail = Array(state.messages.suffix(keep))

        let summaryMessage = PiAgentMessage.custom(.init(
            role: "compaction_summary",
            content: .object([
                "type": .string("compaction_summary"),
                "text": .string(summaryText),
            ]),
            timestamp: timestamp
        ))

        var compacted = state
        compacted.messages = [summaryMessage] + tail
        compacted.streamMessage = nil
        compacted.pendingToolCalls = []
        compacted.isStreaming = false

        return .init(
            state: compacted,
            firstKeptMessageIndex: firstKeptIndex,
            removedMessages: firstKeptIndex,
            keptMessages: tail.count + 1
        )
    }

    private static func tokenEstimate(for text: String) -> Int {
        // ~3.3 bytes/token is more accurate for code-heavy content (common in
        // coding agent context) than the previous 4.0 bytes/token heuristic.
        // More conservative: triggers compaction earlier, avoiding overflow.
        max(1, Int(ceil(Double(text.utf8.count) / 3.3)))
    }

    private static func flatten(_ message: PiAgentMessage) -> String {
        switch message {
        case .user(let msg):
            switch msg.content {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.map {
                    switch $0 {
                    case .text(let text): return text.text
                    case .image(let image): return "[image:\(image.mimeType)]"
                    }
                }.joined(separator: "\n")
            }
        case .assistant(let msg):
            return msg.content.map {
                switch $0 {
                case .text(let t): return t.text
                case .thinking(let t): return t.thinking
                case .toolCall(let c):
                    return "[tool_call \(c.name)]"
                }
            }.joined(separator: "\n")
        case .toolResult(let msg):
            return msg.content.map {
                switch $0 {
                case .text(let t): return t.text
                case .image(let i): return "[tool_image:\(i.mimeType)]"
                }
            }.joined(separator: "\n")
        case .custom(let msg):
            return stringify(msg.content)
        }
    }

    private static func isContextOverflowSignal(_ message: String) -> Bool {
        // Delegate to PiAIOverflow's comprehensive pattern library (15 regex patterns)
        // instead of maintaining a separate, weaker set of checks
        for pattern in PiAIOverflow.patterns() {
            if message.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        // Also check for HTTP 400/413 status codes with no body (matches PiAIOverflow behavior)
        if message.range(of: #"^4(00|13)\s*(status code)?\s*\(no body\)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private static func stringify(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let b):
            return b ? "true" : "false"
        case .number(let n):
            return String(n)
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map(stringify).joined(separator: ",")
        case .object(let obj):
            return obj.keys.sorted().map { key in
                "\(key):\(stringify(obj[key] ?? .null))"
            }.joined(separator: ",")
        }
    }
}

public final class PiCodingAgentCompactionLogStore {
    public typealias Clock = @Sendable () -> Date
    public typealias IDGenerator = @Sendable () -> String

    private let directory: String
    private let fileManager: FileManager
    private let clock: Clock
    private let idGenerator: IDGenerator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: String,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() },
        idGenerator: @escaping IDGenerator = { UUID().uuidString.lowercased() }
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.clock = clock
        self.idGenerator = idGenerator
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(
        sessionID: String,
        mode: PiCodingAgentCompactionMode,
        estimatedTokensBefore: Int,
        threshold: Int,
        removedMessages: Int,
        keptMessages: Int,
        firstKeptMessageIndex: Int,
        summaryText: String
    ) throws -> PiCodingAgentCompactionEntry {
        var entries = try list(sessionID: sessionID)
        let entry = PiCodingAgentCompactionEntry(
            id: idGenerator(),
            sessionID: sessionID,
            mode: mode,
            createdAt: clock(),
            estimatedTokensBefore: estimatedTokensBefore,
            threshold: threshold,
            removedMessages: removedMessages,
            keptMessages: keptMessages,
            firstKeptMessageIndex: firstKeptMessageIndex,
            summaryText: summaryText
        )
        entries.append(entry)
        try save(entries, sessionID: sessionID)
        return entry
    }

    public func list(sessionID: String) throws -> [PiCodingAgentCompactionEntry] {
        let path = filePath(sessionID: sessionID)
        guard fileManager.fileExists(atPath: path) else { return [] }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try decoder.decode([PiCodingAgentCompactionEntry].self, from: data)
        } catch {
            throw PiCodingAgentCompactionError.io("Failed to load compaction log for \(sessionID)")
        }
    }

    public func latest(sessionID: String) throws -> PiCodingAgentCompactionEntry? {
        try list(sessionID: sessionID).last
    }

    private func save(_ entries: [PiCodingAgentCompactionEntry], sessionID: String) throws {
        do {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: filePath(sessionID: sessionID)), options: .atomic)
        } catch {
            throw PiCodingAgentCompactionError.io("Failed to save compaction log for \(sessionID)")
        }
    }

    private func filePath(sessionID: String) -> String {
        (directory as NSString).appendingPathComponent("\(sessionID).json")
    }
}

public final class PiCodingAgentAutoCompactionQueue {
    public struct QueuedMessage: Equatable, Sendable {
        public var text: String
        public var mode: String?

        public init(text: String, mode: String? = nil) {
            self.text = text
            self.mode = mode
        }
    }

    private var isCompacting = false
    private var queued: [QueuedMessage] = []

    public init() {}

    public func beginCompaction() {
        isCompacting = true
    }

    public func endCompaction() {
        isCompacting = false
    }

    @discardableResult
    public func enqueueOrDispatch(_ message: QueuedMessage, dispatch: (QueuedMessage) -> Void) -> Bool {
        if isCompacting {
            queued.append(message)
            return true
        }
        dispatch(message)
        return false
    }

    public func flush(dispatch: (QueuedMessage) -> Void) {
        guard !isCompacting else { return }
        let items = queued
        queued.removeAll()
        for item in items {
            dispatch(item)
        }
    }

    public func queuedMessages() -> [QueuedMessage] {
        queued
    }
}

public final class PiCodingAgentCompactionCoordinator {
    public typealias SummaryBuilder = @Sendable (_ state: PiAgentState, _ mode: PiCodingAgentCompactionMode) -> String
    public typealias TimestampProvider = @Sendable () -> Int64

    private let sessionStore: PiCodingAgentSessionStore
    private let compactionLogStore: PiCodingAgentCompactionLogStore
    private let timestampProvider: TimestampProvider

    public init(
        sessionStore: PiCodingAgentSessionStore,
        compactionLogStore: PiCodingAgentCompactionLogStore,
        timestampProvider: @escaping TimestampProvider = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.sessionStore = sessionStore
        self.compactionLogStore = compactionLogStore
        self.timestampProvider = timestampProvider
    }

    public func maybeAutoCompact(
        sessionID: String,
        config: PiCodingAgentCompactionConfig,
        errorMessage: String? = nil,
        queue: PiCodingAgentAutoCompactionQueue? = nil,
        summaryBuilder: SummaryBuilder
    ) throws -> PiCodingAgentCompactionEntry? {
        let record = try sessionStore.load(id: sessionID)
        let decision = PiCodingAgentCompactionEngine.shouldCompact(state: record.state, config: config, errorMessage: errorMessage)
        guard let mode = decision.mode else { return nil }
        return try compact(
            sessionID: sessionID,
            mode: mode,
            config: config,
            precomputedDecision: decision,
            queue: queue,
            summaryBuilder: summaryBuilder
        )
    }

    public func compact(
        sessionID: String,
        mode: PiCodingAgentCompactionMode,
        config: PiCodingAgentCompactionConfig,
        precomputedDecision: PiCodingAgentCompactionDecision? = nil,
        queue: PiCodingAgentAutoCompactionQueue? = nil,
        summaryBuilder: SummaryBuilder
    ) throws -> PiCodingAgentCompactionEntry {
        let record = try sessionStore.load(id: sessionID)
        let decision = precomputedDecision ?? PiCodingAgentCompactionEngine.shouldCompact(state: record.state, config: config)
        let summary = summaryBuilder(record.state, mode)

        queue?.beginCompaction()
        defer { queue?.endCompaction() }
        let apply = PiCodingAgentCompactionEngine.applyCompaction(
            to: record.state,
            summaryText: summary,
            keepRecentMessages: config.keepRecentMessages,
            timestamp: timestampProvider()
        )
        _ = try sessionStore.save(id: sessionID, state: apply.state, title: record.title)
        let entry = try compactionLogStore.append(
            sessionID: sessionID,
            mode: mode,
            estimatedTokensBefore: decision.estimatedTokens,
            threshold: decision.threshold,
            removedMessages: apply.removedMessages,
            keptMessages: apply.keptMessages,
            firstKeptMessageIndex: apply.firstKeptMessageIndex,
            summaryText: summary
        )
        return entry
    }
}
