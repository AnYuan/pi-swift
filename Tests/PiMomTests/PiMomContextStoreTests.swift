import XCTest
import Foundation
@testable import PiMom
@testable import PiAgentCore
@testable import PiAI

final class PiMomContextStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-mom-context-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSyncLogToContextAppendsOnlyNewUserMessagesSortedAndSkipsBots() throws {
        let channelStore = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: NoopDownloader())
        let contextStore = PiMomContextStore(workingDirectory: tempDir.path)

        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:02Z",
            ts: "2.0",
            user: "U2",
            userName: "bob",
            text: "later",
            attachments: [],
            isBot: false
        ))
        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:01Z",
            ts: "1.0",
            user: "U1",
            userName: "alice",
            text: "first",
            attachments: [],
            isBot: false
        ))
        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:03Z",
            ts: "3.0",
            user: "bot",
            text: "ignored bot message",
            attachments: [],
            isBot: true
        ))

        let synced = try contextStore.syncLogToContext(channelID: "C1")
        XCTAssertEqual(synced, 2)

        let messages = try contextStore.loadMessages(channelID: "C1")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.compactMap(userText), ["[alice]: first", "[bob]: later"])
    }

    func testSyncLogToContextSkipsExcludeSlackTimestampAndAvoidsDuplicateOnSecondSync() throws {
        let channelStore = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: NoopDownloader())
        let contextStore = PiMomContextStore(workingDirectory: tempDir.path)

        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:00Z",
            ts: "100.0",
            user: "U1",
            userName: "alice",
            text: "keep me",
            attachments: [],
            isBot: false
        ))
        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:01Z",
            ts: "101.0",
            user: "U2",
            userName: "bob",
            text: "current",
            attachments: [],
            isBot: false
        ))

        XCTAssertEqual(try contextStore.syncLogToContext(channelID: "C1", excludeSlackTimestamp: "101.0"), 1)
        XCTAssertEqual(try contextStore.syncLogToContext(channelID: "C1", excludeSlackTimestamp: "101.0"), 0)
        XCTAssertEqual(try contextStore.loadMessages(channelID: "C1").compactMap(userText), ["[alice]: keep me"])
    }

    func testSyncLogToContextNormalizesTimestampPrefixAndAttachmentBlockForDedupe() throws {
        let channelStore = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: NoopDownloader())
        let contextStore = PiMomContextStore(workingDirectory: tempDir.path)

        try contextStore.appendMessages(channelID: "C1", messages: [
            .user(.init(
                content: .parts([.text(.init(text:
                    "[2026-02-24 10:00:00+00:00] [alice]: hello\n\n<slack_attachments>\nC1/attachments/a.txt\n</slack_attachments>"
                ))]),
                timestamp: 1
            ))
        ])

        _ = try channelStore.logMessage(channelID: "C1", message: .init(
            date: "2026-02-24T10:00:01Z",
            ts: "2.0",
            user: "U1",
            userName: "alice",
            text: "hello",
            attachments: [],
            isBot: false
        ))

        XCTAssertEqual(try contextStore.syncLogToContext(channelID: "C1"), 0)
        XCTAssertEqual(try contextStore.loadMessages(channelID: "C1").count, 1)
    }
}

private func userText(_ message: PiAgentMessage) -> String? {
    guard case .user(let user) = message else { return nil }
    switch user.content {
    case .text(let text):
        return text
    case .parts(let parts):
        for part in parts {
            if case .text(let value) = part {
                return value.text
            }
        }
        return nil
    }
}

private final class NoopDownloader: PiMomAttachmentDownloading, @unchecked Sendable {
    func download(url: String, authToken: String?) throws -> Data {
        _ = url
        _ = authToken
        return Data()
    }
}
