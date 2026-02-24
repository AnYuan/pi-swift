import XCTest
@testable import PiTUI

final class PiTUIEditorHistoryTests: XCTestCase {
    func testNavigateUpDoesNothingWhenHistoryEmpty() {
        let history = PiTUIEditorHistory()
        XCTAssertNil(history.navigateUp(currentText: ""))
        XCTAssertEqual(history.historyIndex, -1)
    }

    func testAddToHistoryIgnoresEmptyAndConsecutiveDuplicates() {
        let history = PiTUIEditorHistory()
        history.addToHistory("")
        history.addToHistory("   ")
        history.addToHistory("hello")
        history.addToHistory("hello")
        history.addToHistory("hello ")
        history.addToHistory("world")
        history.addToHistory("hello")

        XCTAssertEqual(history.entries(), ["hello", "world", "hello"])
    }

    func testHistoryIsLimitedTo100Entries() {
        let history = PiTUIEditorHistory()
        for i in 0..<120 {
            history.addToHistory("item-\(i)")
        }

        XCTAssertEqual(history.count, 100)
        XCTAssertEqual(history.entries().first, "item-119")
        XCTAssertEqual(history.entries().last, "item-20")
    }

    func testNavigateUpAndDownRestoresCurrentDraft() {
        let history = PiTUIEditorHistory()
        history.addToHistory("older")
        history.addToHistory("newer")

        XCTAssertEqual(history.navigateUp(currentText: "draft"), "newer")
        XCTAssertEqual(history.historyIndex, 0)
        XCTAssertEqual(history.navigateUp(currentText: "ignored"), "older")
        XCTAssertEqual(history.historyIndex, 1)
        XCTAssertNil(history.navigateUp(currentText: "ignored"))
        XCTAssertEqual(history.historyIndex, 1)

        XCTAssertEqual(history.navigateDown(currentText: "ignored"), "newer")
        XCTAssertEqual(history.historyIndex, 0)
        XCTAssertEqual(history.navigateDown(currentText: "ignored"), "draft")
        XCTAssertEqual(history.historyIndex, -1)
    }

    func testUpdateCurrentDraftExitsHistoryBrowsing() {
        let history = PiTUIEditorHistory()
        history.addToHistory("first")
        history.addToHistory("second")

        XCTAssertEqual(history.navigateUp(currentText: "draft"), "second")
        XCTAssertTrue(history.isBrowsing)

        history.updateCurrentDraft("edited")
        XCTAssertFalse(history.isBrowsing)
        XCTAssertEqual(history.navigateUp(currentText: "edited"), "second")
        XCTAssertEqual(history.navigateDown(currentText: "ignored"), "edited")
    }
}
