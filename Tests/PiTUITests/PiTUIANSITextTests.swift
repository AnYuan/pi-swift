import XCTest
@testable import PiTUI

final class PiTUIANSITextTests: XCTestCase {
    func testVisibleWidthIgnoresCSIEscapeSequences() {
        let value = "\u{001B}[31mHello\u{001B}[0m"
        XCTAssertEqual(PiTUIANSIText.visibleWidth(value), 5)
    }

    func testVisibleWidthIgnoresOSC8HyperlinkSequences() {
        let value = "\u{001B}]8;;https://example.com\u{0007}Link\u{001B}]8;;\u{0007}"
        XCTAssertEqual(PiTUIANSIText.visibleWidth(value), 4)
    }

    func testVisibleWidthTreatsWideAndCombiningScalarsCorrectly() {
        XCTAssertEqual(PiTUIANSIText.visibleWidth("你"), 2)
        XCTAssertEqual(PiTUIANSIText.visibleWidth("e\u{0301}"), 1)
        XCTAssertEqual(PiTUIANSIText.visibleWidth("A你B"), 4)
    }

    func testTruncateToVisibleWidthPreservesANSISequences() {
        let value = "\u{001B}[31mabcdef\u{001B}[0m"
        let truncated = PiTUIANSIText.truncateToVisibleWidth(value, maxWidth: 3)
        XCTAssertEqual(truncated, "\u{001B}[31mabc")
        XCTAssertEqual(PiTUIANSIText.visibleWidth(truncated), 3)
    }

    func testTruncateToVisibleWidthHandlesWideCharactersWithoutSplitting() {
        XCTAssertEqual(PiTUIANSIText.truncateToVisibleWidth("你A", maxWidth: 1), "")
        XCTAssertEqual(PiTUIANSIText.truncateToVisibleWidth("你A", maxWidth: 2), "你")
        XCTAssertEqual(PiTUIANSIText.truncateToVisibleWidth("你A", maxWidth: 3), "你A")
    }

    func testEnsureLineResetAppendsResetOnlyWhenANSIPresent() {
        XCTAssertEqual(PiTUIANSIText.ensureLineReset("plain"), "plain")
        XCTAssertEqual(
            PiTUIANSIText.ensureLineReset("\u{001B}[31mred"),
            "\u{001B}[31mred\u{001B}[0m"
        )
        XCTAssertEqual(
            PiTUIANSIText.ensureLineReset("\u{001B}[31mred\u{001B}[0m"),
            "\u{001B}[31mred\u{001B}[0m"
        )
    }
}
