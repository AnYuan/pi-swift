import XCTest
@testable import PiTUI

final class PiTUISelectListTests: XCTestCase {
    private let theme = PiTUISelectListTheme.plain

    func testNormalizesMultilineDescriptionsToSingleLine() {
        let items = [
            PiTUISelectItem(value: "test", label: "test", description: "Line one\nLine two\r\nLine three")
        ]
        let list = PiTUISelectList(items: items, maxVisible: 5, theme: theme)

        let rendered = list.render(width: 100)
        XCTAssertFalse(rendered.isEmpty)
        XCTAssertFalse(rendered[0].contains("\n"))
        XCTAssertTrue(rendered[0].contains("Line one Line two Line three"))
    }

    func testUpDownNavigationWrapsAndSelectionChangeFires() {
        let items = [
            PiTUISelectItem(value: "a", label: "A"),
            PiTUISelectItem(value: "b", label: "B"),
            PiTUISelectItem(value: "c", label: "C")
        ]
        let list = PiTUISelectList(items: items, maxVisible: 5, theme: theme)
        var changes: [String] = []
        list.onSelectionChange = { changes.append($0.value) }

        list.handleInput("\u{001B}[A") // up wraps to last
        XCTAssertEqual(list.getSelectedItem()?.value, "c")
        list.handleInput("\u{001B}[B") // down wraps to first
        XCTAssertEqual(list.getSelectedItem()?.value, "a")

        XCTAssertEqual(changes, ["c", "a"])
    }

    func testConfirmAndCancelCallbacks() {
        let items = [PiTUISelectItem(value: "x", label: "X")]
        let list = PiTUISelectList(items: items, maxVisible: 5, theme: theme)
        var selected: [String] = []
        var cancelled = 0
        list.onSelect = { selected.append($0.value) }
        list.onCancel = { cancelled += 1 }

        list.handleInput("\r")
        list.handleInput("\u{001B}")

        XCTAssertEqual(selected, ["x"])
        XCTAssertEqual(cancelled, 1)
    }

    func testFilterResetsSelectionAndNoMatchMessageRenders() {
        let items = [
            PiTUISelectItem(value: "open", label: "Open"),
            PiTUISelectItem(value: "close", label: "Close")
        ]
        let list = PiTUISelectList(items: items, maxVisible: 5, theme: theme)
        list.setSelectedIndex(1)
        XCTAssertEqual(list.getSelectedItem()?.value, "close")

        list.setFilter("op")
        XCTAssertEqual(list.getSelectedItem()?.value, "open")

        list.setFilter("zzz")
        XCTAssertNil(list.getSelectedItem())
        XCTAssertEqual(list.render(width: 40), ["  No matching commands"])
    }

    func testRenderAddsScrollInfoWhenListExceedsMaxVisible() {
        let items = (0..<10).map { PiTUISelectItem(value: "v\($0)", label: "Item \($0)") }
        let list = PiTUISelectList(items: items, maxVisible: 3, theme: theme)
        list.setSelectedIndex(5)

        let rendered = list.render(width: 40)
        XCTAssertEqual(rendered.count, 4) // 3 items + scroll info
        XCTAssertTrue(rendered.last?.contains("(6/10)") == true)
    }
}
