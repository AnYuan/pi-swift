import XCTest
import Foundation
@testable import PiMom

final class PiMomChannelStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-mom-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testGenerateLocalFilenameSanitizesAndUsesSlackTimestampMillis() throws {
        let store = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: RecordingDownloader())
        let name = store.generateLocalFilename(originalName: "my bad:file?.png", timestamp: "1234567890.123456")
        XCTAssertEqual(name, "1234567890123_my_bad_file_.png")
    }

    func testProcessAttachmentsQueuesDownloadsAndDrainWritesFiles() throws {
        let downloader = RecordingDownloader(dataByURL: [
            "https://files.example/a": Data("A".utf8),
            "https://files.example/b": Data("B".utf8),
        ])
        let store = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: downloader)

        let attachments = store.processAttachments(
            channelID: "C1",
            files: [
                .init(name: "a.txt", urlPrivateDownload: "https://files.example/a"),
                .init(name: "b.txt", urlPrivate: "https://files.example/b"),
                .init(name: nil, urlPrivateDownload: "https://files.example/skip")
            ],
            timestamp: "1000.500000"
        )

        XCTAssertEqual(attachments.count, 2)
        XCTAssertEqual(attachments[0].local, "C1/attachments/1000500_a.txt")
        XCTAssertEqual(store.pendingDownloadCount, 2)

        store.processPendingDownloads()

        XCTAssertEqual(store.pendingDownloadCount, 0)
        XCTAssertEqual(downloader.calls.count, 2)
        let firstPath = tempDir.appendingPathComponent(attachments[0].local).path
        let secondPath = tempDir.appendingPathComponent(attachments[1].local).path
        XCTAssertEqual(try String(contentsOfFile: firstPath, encoding: .utf8), "A")
        XCTAssertEqual(try String(contentsOfFile: secondPath, encoding: .utf8), "B")
    }

    func testLogMessageDedupeAndLastTimestamp() throws {
        let store = PiMomChannelStore(workingDirectory: tempDir.path, attachmentDownloader: RecordingDownloader())
        let message = PiMomLoggedMessage(
            date: nil,
            ts: "1234567890.123456",
            user: "U1",
            userName: "alice",
            displayName: "Alice",
            text: "hello",
            attachments: [],
            isBot: false
        )

        XCTAssertTrue(try store.logMessage(channelID: "C1", message: message))
        XCTAssertFalse(try store.logMessage(channelID: "C1", message: message))
        XCTAssertEqual(store.lastTimestamp(channelID: "C1"), "1234567890.123456")

        let logPath = tempDir.appendingPathComponent("C1/log.jsonl")
        let lines = try String(contentsOf: logPath, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("\"date\""))
        XCTAssertTrue(lines[0].contains("\"text\":\"hello\""))
    }
}

private final class RecordingDownloader: PiMomAttachmentDownloading, @unchecked Sendable {
    private let dataByURL: [String: Data]
    private(set) var calls: [String] = []

    init(dataByURL: [String: Data] = [:]) {
        self.dataByURL = dataByURL
    }

    func download(url: String, authToken: String?) throws -> Data {
        _ = authToken
        calls.append(url)
        return dataByURL[url] ?? Data()
    }
}
