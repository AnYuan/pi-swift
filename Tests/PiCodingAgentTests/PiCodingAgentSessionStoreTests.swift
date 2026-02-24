import XCTest
import Foundation
import PiAI
import PiAgentCore
@testable import PiCodingAgent

final class PiCodingAgentSessionStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testSaveNewAndLoadRoundTripsSessionState() throws {
        let clock = FixedClock([
            date(1000)
        ])
        let store = PiCodingAgentSessionStore(
            directory: tempDir.path,
            clock: { clock.next() },
            idGenerator: { "session-a" }
        )

        let saved = try store.saveNew(state: sampleState(modelID: "gpt-5"), title: "Test")
        let loaded = try store.load(id: "session-a")

        XCTAssertEqual(saved, loaded)
        XCTAssertEqual(loaded.title, "Test")
        XCTAssertEqual(loaded.state.model.id, "gpt-5")
    }

    func testSaveUpdatesExistingSessionTimestampAndPreservesCreatedAt() throws {
        let clock = FixedClock([date(1000), date(2000)])
        let store = PiCodingAgentSessionStore(
            directory: tempDir.path,
            clock: { clock.next() },
            idGenerator: { "s1" }
        )

        _ = try store.saveNew(state: sampleState(modelID: "gpt-5"), title: "Session")
        let updated = try store.save(id: "s1", state: sampleState(modelID: "gpt-4.1"))

        XCTAssertEqual(updated.createdAt, date(1000))
        XCTAssertEqual(updated.updatedAt, date(2000))
        XCTAssertEqual(updated.state.model.id, "gpt-4.1")
        XCTAssertEqual(updated.title, "Session")
    }

    func testListSessionsSortsByUpdatedAtDescending() throws {
        let clock = FixedClock([date(1000), date(2000), date(3000)])
        let store = PiCodingAgentSessionStore(directory: tempDir.path, clock: { clock.next() }, idGenerator: {
            UUID().uuidString.lowercased()
        })

        let a = try store.save(id: "a", state: sampleState(modelID: "1"))
        _ = a
        let b = try store.save(id: "b", state: sampleState(modelID: "2"))
        _ = b
        let c = try store.save(id: "c", state: sampleState(modelID: "3"))
        _ = c

        let listed = try store.listSessions()
        XCTAssertEqual(listed.map(\.id), ["c", "b", "a"])
    }

    func testResolveContinueUsesExplicitIDOrLatest() throws {
        let clock = FixedClock([date(1000), date(2000)])
        let store = PiCodingAgentSessionStore(directory: tempDir.path, clock: { clock.next() }, idGenerator: {
            UUID().uuidString.lowercased()
        })
        _ = try store.save(id: "old", state: sampleState(modelID: "old"))
        _ = try store.save(id: "new", state: sampleState(modelID: "new"))

        XCTAssertEqual(try store.resolveContinue(sessionID: "old").id, "old")
        XCTAssertEqual(try store.resolveContinue(sessionID: nil).id, "new")
    }

    func testResolveContinueErrorsWhenNoSessionsExist() throws {
        let store = PiCodingAgentSessionStore(directory: tempDir.path)
        XCTAssertThrowsError(try store.resolveContinue(sessionID: nil)) { error in
            XCTAssertEqual(error as? PiCodingAgentSessionStoreError, .io("No sessions available to continue"))
        }
    }

    private func sampleState(modelID: String) -> PiAgentState {
        .empty(model: .init(provider: "openai", id: modelID))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

private final class FixedClock: @unchecked Sendable {
    private var values: [Date]
    private var index = 0

    init(_ values: [Date]) {
        self.values = values
    }

    func next() -> Date {
        guard !values.isEmpty else { return Date(timeIntervalSince1970: 0) }
        defer { index = min(index + 1, values.count - 1) }
        return values[index]
    }
}
