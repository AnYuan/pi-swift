import XCTest
@testable import PiTUI

final class PiTUIMarkdownTests: XCTestCase {
    func testWrapsParagraphTextToWidth() {
        let md = PiTUIMarkdown("This is a markdown paragraph that should wrap across multiple lines.")

        let lines = md.render(width: 18)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { PiTUIANSIText.visibleWidth($0) <= 18 })
    }

    func testRendersBasicHeadingBulletQuoteAndLinkInline() {
        let md = PiTUIMarkdown(
            """
            # Title
            - **Bold** item
            > Quote line
            Link: [OpenAI](https://openai.com)
            """
        )

        let lines = md.render(width: 80)
        XCTAssertTrue(lines.contains("TITLE"))
        XCTAssertTrue(lines.contains { $0.contains("• Bold item") })
        XCTAssertTrue(lines.contains { $0.contains("│ Quote line") })
        XCTAssertTrue(lines.contains { $0.contains("OpenAI (https://openai.com)") })
    }

    func testSkipsWrappingForImageProtocolLine() {
        let imageLine = "\u{001B}]1337;File=inline=1:" + String(repeating: "A", count: 300) + "\u{0007}"
        let md = PiTUIMarkdown("before\n\(imageLine)\nafter")

        let lines = md.render(width: 20)
        XCTAssertTrue(lines.contains("before"))
        XCTAssertTrue(lines.contains(imageLine))
        XCTAssertTrue(lines.contains("after"))
    }

    func testCachesByWidthAndInvalidatesOnSourceChange() {
        let md = PiTUIMarkdown("hello world")

        _ = md.render(width: 20)
        _ = md.render(width: 20)
        XCTAssertEqual(md.debugRenderPasses, 1)

        _ = md.render(width: 10)
        XCTAssertEqual(md.debugRenderPasses, 2)

        md.setMarkdown("updated")
        _ = md.render(width: 10)
        XCTAssertEqual(md.debugRenderPasses, 3)
    }
}
