import XCTest
@testable import PiTUI

final class PiTUISettingsListTests: XCTestCase {
    private let theme = PiTUISettingsListTheme.plain

    final class FakeSubmenu: PiTUIInteractiveComponent {
        let onDone: (String?) -> Void
        private(set) var inputs: [String] = []

        init(onDone: @escaping (String?) -> Void) {
            self.onDone = onDone
        }

        func render(width: Int) -> [String] {
            ["SUBMENU"]
        }

        func invalidate() {}

        func handleInput(_ data: String) {
            inputs.append(data)
            if data == "\r" {
                onDone("Updated")
            } else if data == "\u{001B}" {
                onDone(nil)
            }
        }
    }

    func testRenderAlignsLabelAndValueAndShowsHint() {
        let list = PiTUISettingsList(
            items: [
                .init(id: "theme", label: "Theme", currentValue: "Dark", values: ["Dark", "Light"]),
                .init(id: "vim", label: "Vim Mode", currentValue: "On", values: ["On", "Off"])
            ],
            maxVisible: 5,
            theme: theme
        )

        let lines = list.render(width: 60)
        XCTAssertTrue(lines[0].contains("Theme"))
        XCTAssertTrue(lines[0].contains("Dark"))
        XCTAssertTrue(lines.last?.contains("Enter/Space to change") == true)
    }

    func testUpDownNavigationWrapsAndSelectionMoves() {
        let list = PiTUISettingsList(
            items: [
                .init(id: "a", label: "A", currentValue: "1"),
                .init(id: "b", label: "B", currentValue: "2"),
                .init(id: "c", label: "C", currentValue: "3")
            ],
            maxVisible: 5,
            theme: theme
        )

        list.handleInput("\u{001B}[A")
        XCTAssertEqual(list.getSelectedItem()?.id, "c")

        list.handleInput("\u{001B}[B")
        XCTAssertEqual(list.getSelectedItem()?.id, "a")
    }

    func testEnterAndSpaceCycleValuesAndEmitOnChange() {
        let list = PiTUISettingsList(
            items: [.init(id: "theme", label: "Theme", currentValue: "Dark", values: ["Dark", "Light"])],
            theme: theme
        )
        var changes: [(String, String)] = []
        list.onChange = { changes.append(($0, $1)) }

        list.handleInput("\r")
        XCTAssertEqual(list.getSelectedItem()?.currentValue, "Light")
        list.handleInput(" ")
        XCTAssertEqual(list.getSelectedItem()?.currentValue, "Dark")

        XCTAssertEqual(changes.map(\.0), ["theme", "theme"])
        XCTAssertEqual(changes.map(\.1), ["Light", "Dark"])
    }

    func testCancelInvokesCallback() {
        let list = PiTUISettingsList(items: [.init(id: "a", label: "A", currentValue: "1")], theme: theme)
        var cancelled = 0
        list.onCancel = { cancelled += 1 }

        list.handleInput("\u{001B}")
        XCTAssertEqual(cancelled, 1)
    }

    func testSearchFiltersItemsAndBackspaceRestoresMatches() {
        let list = PiTUISettingsList(
            items: [
                .init(id: "theme", label: "Theme", currentValue: "Dark"),
                .init(id: "verbose", label: "Verbose Logging", currentValue: "Off")
            ],
            theme: theme,
            options: .init(enableSearch: true)
        )

        list.handleInput("v")
        XCTAssertEqual(list.getSearchQuery(), "v")
        XCTAssertEqual(list.getSelectedItem()?.id, "verbose")
        XCTAssertTrue(list.render(width: 60).joined(separator: "\n").contains("Search: v"))

        list.handleInput("\u{007F}") // backspace
        XCTAssertEqual(list.getSearchQuery(), "")
        XCTAssertEqual(list.getSelectedItem()?.id, "theme")
    }

    func testRenderShowsNoMatchMessageWhenSearchFiltersEverything() {
        let list = PiTUISettingsList(
            items: [.init(id: "theme", label: "Theme", currentValue: "Dark")],
            theme: theme,
            options: .init(enableSearch: true)
        )

        list.handleInput("z")
        let rendered = list.render(width: 50)
        XCTAssertTrue(rendered.joined(separator: "\n").contains("No matching settings"))
    }

    func testRenderShowsSelectedDescriptionWrapped() {
        let list = PiTUISettingsList(
            items: [
                .init(
                    id: "theme",
                    label: "Theme",
                    description: "This is a long description that should wrap into multiple lines.",
                    currentValue: "Dark"
                )
            ],
            theme: theme
        )

        let rendered = list.render(width: 24)
        let descLines = rendered.filter { $0.hasPrefix("  This") || $0.hasPrefix("  should") || $0.hasPrefix("  lines.") }
        XCTAssertFalse(descLines.isEmpty)
    }

    func testScrollIndicatorRendersWhenClipped() {
        let items = (0..<10).map {
            PiTUISettingItem(id: "s\($0)", label: "Setting \($0)", currentValue: "Value")
        }
        let list = PiTUISettingsList(items: items, maxVisible: 3, theme: theme)

        list.handleInput("\u{001B}[B")
        list.handleInput("\u{001B}[B")
        list.handleInput("\u{001B}[B")
        list.handleInput("\u{001B}[B")

        XCTAssertTrue(list.render(width: 60).contains { $0.contains("(5/10)") })
    }

    func testSubmenuRenderAndDoneUpdatesValueAndRestoresList() {
        var submenuCreated = 0
        let list = PiTUISettingsList(
            items: [
                .init(
                    id: "mode",
                    label: "Mode",
                    currentValue: "Old",
                    submenu: { currentValue, done in
                        XCTAssertEqual(currentValue, "Old")
                        submenuCreated += 1
                        return FakeSubmenu(onDone: done)
                    }
                )
            ],
            theme: theme
        )
        var changes: [(String, String)] = []
        list.onChange = { changes.append(($0, $1)) }

        list.handleInput("\r")
        XCTAssertEqual(submenuCreated, 1)
        XCTAssertEqual(list.render(width: 40), ["SUBMENU"])

        list.handleInput("\r")
        XCTAssertEqual(list.getSelectedItem()?.currentValue, "Updated")
        XCTAssertTrue(list.render(width: 40).joined(separator: "\n").contains("Mode"))
        XCTAssertEqual(changes.map(\.0), ["mode"])
        XCTAssertEqual(changes.map(\.1), ["Updated"])
    }

    func testSubmenuCancelClosesWithoutChangingValue() {
        let list = PiTUISettingsList(
            items: [
                .init(
                    id: "mode",
                    label: "Mode",
                    currentValue: "Old",
                    submenu: { _, done in FakeSubmenu(onDone: done) }
                )
            ],
            theme: theme
        )
        var changes = 0
        list.onChange = { _, _ in changes += 1 }

        list.handleInput("\r")
        XCTAssertEqual(list.render(width: 40), ["SUBMENU"])

        list.handleInput("\u{001B}")
        XCTAssertEqual(list.getSelectedItem()?.currentValue, "Old")
        XCTAssertEqual(changes, 0)
        XCTAssertTrue(list.render(width: 40).joined(separator: "\n").contains("Mode"))
    }
}
