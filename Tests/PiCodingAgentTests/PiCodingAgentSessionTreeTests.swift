import XCTest
import Foundation
@testable import PiCodingAgent

final class PiCodingAgentSessionTreeTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testCreateRootAndBranchPersistsNodes() throws {
        let clock = FixedTreeClock([date(1000), date(2000), date(3000)])
        let store = PiCodingAgentSessionTreeStore(
            filePath: tempDir.appendingPathComponent("tree/index.json").path,
            clock: { clock.next() }
        )

        try store.createRoot(sessionID: "root")
        try store.branch(from: "root", childID: "child-a")
        try store.branch(from: "root", childID: "child-b")

        let root = try store.node(id: "root")
        XCTAssertEqual(root.childIDs, ["child-a", "child-b"])
        XCTAssertNil(root.parentID)

        let child = try store.node(id: "child-a")
        XCTAssertEqual(child.parentID, "root")
    }

    func testChildrenAncestorsAndPathTraversal() throws {
        let clock = FixedTreeClock([date(1), date(2), date(3)])
        let store = PiCodingAgentSessionTreeStore(filePath: tempDir.appendingPathComponent("tree.json").path, clock: { clock.next() })

        try store.createRoot(sessionID: "r")
        try store.branch(from: "r", childID: "a")
        try store.branch(from: "a", childID: "b")

        XCTAssertEqual(try store.children(of: "r").map(\.id), ["a"])
        XCTAssertEqual(try store.ancestors(of: "b").map(\.id), ["a", "r"])
        XCTAssertEqual(try store.pathToRoot(of: "b").map(\.id), ["r", "a", "b"])
    }

    func testErrorsOnDuplicateNodesAndMissingParents() throws {
        let store = PiCodingAgentSessionTreeStore(filePath: tempDir.appendingPathComponent("tree.json").path)
        try store.createRoot(sessionID: "r")

        XCTAssertThrowsError(try store.createRoot(sessionID: "r")) { error in
            XCTAssertEqual(error as? PiCodingAgentSessionTreeError, .nodeExists("r"))
        }
        XCTAssertThrowsError(try store.branch(from: "missing", childID: "x")) { error in
            XCTAssertEqual(error as? PiCodingAgentSessionTreeError, .parentNotFound("missing"))
        }
        XCTAssertThrowsError(try store.node(id: "missing")) { error in
            XCTAssertEqual(error as? PiCodingAgentSessionTreeError, .nodeNotFound("missing"))
        }
    }
}

private final class FixedTreeClock: @unchecked Sendable {
    private var dates: [Date]
    private var index = 0

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        guard !dates.isEmpty else { return Date(timeIntervalSince1970: 0) }
        defer { index = min(index + 1, dates.count - 1) }
        return dates[index]
    }
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
