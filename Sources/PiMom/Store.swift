import Foundation

public struct PiMomAttachment: Codable, Equatable, Sendable {
    public var original: String
    public var local: String

    public init(original: String, local: String) {
        self.original = original
        self.local = local
    }
}

public struct PiMomLoggedMessage: Codable, Equatable, Sendable {
    public var date: String?
    public var ts: String
    public var user: String
    public var userName: String?
    public var displayName: String?
    public var text: String
    public var attachments: [PiMomAttachment]
    public var isBot: Bool

    public init(
        date: String? = nil,
        ts: String,
        user: String,
        userName: String? = nil,
        displayName: String? = nil,
        text: String,
        attachments: [PiMomAttachment],
        isBot: Bool
    ) {
        self.date = date
        self.ts = ts
        self.user = user
        self.userName = userName
        self.displayName = displayName
        self.text = text
        self.attachments = attachments
        self.isBot = isBot
    }
}

public protocol PiMomAttachmentDownloading: Sendable {
    func download(url: String, authToken: String?) throws -> Data
}

public final class PiMomURLSessionAttachmentDownloader: PiMomAttachmentDownloading, @unchecked Sendable {
    public init() {}

    public func download(url: String, authToken: String?) throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        let semaphore = DispatchSemaphore(value: 0)
        let state = DownloadState()
        URLSession.shared.dataTask(with: request) { data, _, error in
            state.data = data
            state.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let responseError = state.error { throw responseError }
        return state.data ?? Data()
    }

    private final class DownloadState: @unchecked Sendable {
        var data: Data?
        var error: Error?
    }
}

public final class PiMomChannelStore: @unchecked Sendable {
    private struct PendingDownload {
        var localPath: String
        var url: String
    }

    public let workingDirectory: String
    public let botToken: String?
    private let attachmentDownloader: any PiMomAttachmentDownloading
    private var pendingDownloads: [PendingDownload] = []
    private var recentlyLogged: Set<String> = []

    public init(
        workingDirectory: String,
        botToken: String? = nil,
        attachmentDownloader: any PiMomAttachmentDownloading = PiMomURLSessionAttachmentDownloader()
    ) {
        self.workingDirectory = workingDirectory
        self.botToken = botToken
        self.attachmentDownloader = attachmentDownloader
        try? FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
    }

    public var pendingDownloadCount: Int {
        pendingDownloads.count
    }

    public func channelDirectory(_ channelID: String) -> String {
        let path = (workingDirectory as NSString).appendingPathComponent(channelID)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    public func generateLocalFilename(originalName: String, timestamp: String) -> String {
        let millis = Int((Double(timestamp) ?? 0) * 1000)
        let sanitized = originalName.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" { return ch }
            return "_"
        }
        return "\(millis)_\(String(sanitized))"
    }

    public func processAttachments(
        channelID: String,
        files: [PiMomSlackFileRef],
        timestamp: String
    ) -> [PiMomAttachment] {
        var attachments: [PiMomAttachment] = []
        for file in files {
            guard let name = file.name else { continue }
            guard let url = file.urlPrivateDownload ?? file.urlPrivate else { continue }

            let filename = generateLocalFilename(originalName: name, timestamp: timestamp)
            let localPath = "\(channelID)/attachments/\(filename)"
            attachments.append(.init(original: name, local: localPath))
            pendingDownloads.append(.init(localPath: localPath, url: url))
        }
        return attachments
    }

    public func processPendingDownloads() {
        while !pendingDownloads.isEmpty {
            let item = pendingDownloads.removeFirst()
            do {
                let data = try attachmentDownloader.download(url: item.url, authToken: botToken)
                let filePath = (workingDirectory as NSString).appendingPathComponent(item.localPath)
                let dir = (filePath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            } catch {
                // Continue draining on failures to match best-effort queue behavior.
            }
        }
    }

    @discardableResult
    public func logMessage(channelID: String, message: PiMomLoggedMessage) throws -> Bool {
        let dedupeKey = "\(channelID):\(message.ts)"
        guard !recentlyLogged.contains(dedupeKey) else { return false }
        recentlyLogged.insert(dedupeKey)

        let logPath = ((channelDirectory(channelID) as NSString).appendingPathComponent("log.jsonl"))
        var value = message
        if value.date == nil {
            value.date = dateString(from: value.ts)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
        if FileManager.default.fileExists(atPath: logPath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
        return true
    }

    public func logBotResponse(channelID: String, text: String, ts: String) throws {
        _ = try logMessage(channelID: channelID, message: .init(
            date: Date().ISO8601Format(),
            ts: ts,
            user: "bot",
            text: text,
            attachments: [],
            isBot: true
        ))
    }

    public func lastTimestamp(channelID: String) -> String? {
        let path = ((workingDirectory as NSString).appendingPathComponent(channelID) as NSString).appendingPathComponent("log.jsonl")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n")
        guard let last = lines.last, let data = String(last).data(using: .utf8),
              let message = try? JSONDecoder().decode(PiMomLoggedMessage.self, from: data) else { return nil }
        return message.ts
    }

    private func dateString(from timestamp: String) -> String {
        if timestamp.contains("."), let seconds = Double(timestamp) {
            return Date(timeIntervalSince1970: seconds).ISO8601Format()
        }
        if let millis = Double(timestamp) {
            return Date(timeIntervalSince1970: millis / 1000.0).ISO8601Format()
        }
        return Date().ISO8601Format()
    }
}
