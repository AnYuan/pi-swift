import Foundation
import PiAI
import PiAgentCore

public final class PiMomContextStore: @unchecked Sendable {
    private let workingDirectory: String
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(workingDirectory: String, fileManager: FileManager = .default) {
        self.workingDirectory = workingDirectory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func contextFilePath(channelID: String) -> String {
        let channelDir = (workingDirectory as NSString).appendingPathComponent(channelID)
        return (channelDir as NSString).appendingPathComponent("context.jsonl")
    }

    public func loadMessages(channelID: String) throws -> [PiAgentMessage] {
        let path = contextFilePath(channelID: channelID)
        guard fileManager.fileExists(atPath: path) else { return [] }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return try content
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let data = Data(String(line).utf8)
                return try decoder.decode(PiAgentMessage.self, from: data)
            }
    }

    public func appendMessages(channelID: String, messages: [PiAgentMessage]) throws {
        guard !messages.isEmpty else { return }
        let path = contextFilePath(channelID: channelID)
        let channelDir = ((workingDirectory as NSString).appendingPathComponent(channelID))
        try fileManager.createDirectory(atPath: channelDir, withIntermediateDirectories: true, attributes: nil)

        var buffer = ""
        for message in messages {
            let line = String(decoding: try encoder.encode(message), as: UTF8.self)
            buffer += line + "\n"
        }

        if fileManager.fileExists(atPath: path) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(buffer.utf8))
        } else {
            try buffer.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    public func syncLogToContext(channelID: String, excludeSlackTimestamp: String? = nil) throws -> Int {
        let channelDir = (workingDirectory as NSString).appendingPathComponent(channelID)
        let logPath = (channelDir as NSString).appendingPathComponent("log.jsonl")
        guard fileManager.fileExists(atPath: logPath) else { return 0 }

        let existingMessages = try loadMessages(channelID: channelID)
        var existingNormalizedTexts = Set<String>()
        for message in existingMessages {
            for text in extractUserTexts(message) {
                existingNormalizedTexts.insert(normalizeContextUserText(text))
            }
        }

        let content = try String(contentsOfFile: logPath, encoding: .utf8)
        var pending: [(timestamp: Int64, message: PiAgentMessage)] = []

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(rawLine).data(using: .utf8) else { continue }
            guard let logMessage = try? decoder.decode(PiMomLoggedMessage.self, from: data) else { continue }
            if logMessage.isBot { continue }
            if let excludeSlackTimestamp, logMessage.ts == excludeSlackTimestamp { continue }
            guard !logMessage.ts.isEmpty else { continue }

            let author = logMessage.userName ?? logMessage.user
            let composed = "[\(author)]: \(logMessage.text)"
            let normalized = normalizeContextUserText(composed)
            if existingNormalizedTexts.contains(normalized) { continue }

            let timestamp = parseTimestamp(logMessage)
            let agentMessage = PiAgentMessage.user(.init(
                content: .parts([.text(.init(text: composed))]),
                timestamp: timestamp
            ))
            pending.append((timestamp, agentMessage))
            existingNormalizedTexts.insert(normalized)
        }

        if pending.isEmpty { return 0 }
        pending.sort { $0.timestamp < $1.timestamp }
        try appendMessages(channelID: channelID, messages: pending.map(\.message))
        return pending.count
    }

    private func extractUserTexts(_ message: PiAgentMessage) -> [String] {
        guard case .user(let userMessage) = message else { return [] }
        switch userMessage.content {
        case .text(let text):
            return [text]
        case .parts(let parts):
            return parts.compactMap {
                guard case .text(let value) = $0 else { return nil }
                return value.text
            }
        }
    }

    private func normalizeContextUserText(_ text: String) -> String {
        var result = text
        result = stripTimestampPrefix(result)
        if let range = result.range(of: "\n\n<slack_attachments>\n") {
            result = String(result[..<range.lowerBound])
        }
        return result
    }

    private func stripTimestampPrefix(_ text: String) -> String {
        let pattern = #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\] "#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func parseTimestamp(_ logMessage: PiMomLoggedMessage) -> Int64 {
        if let date = logMessage.date, let parsed = ISO8601DateFormatter().date(from: date) {
            return Int64(parsed.timeIntervalSince1970 * 1000)
        }
        if let seconds = Double(logMessage.ts) {
            return Int64(seconds * 1000)
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}
