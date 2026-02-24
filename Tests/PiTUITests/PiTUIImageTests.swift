import XCTest
@testable import PiTUI

final class PiTUIImageTests: XCTestCase {
    func testFallbackRendersWhenImageProtocolUnavailable() {
        let image = PiTUIImage(
            base64Data: "ZmFrZQ==",
            mimeType: "image/png",
            dimensions: .init(widthPx: 800, heightPx: 600),
            theme: .plain,
            options: .init(filename: "test.png"),
            capabilitiesProvider: { .init(images: nil) }
        )

        let lines = image.render(width: 80)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("image/png"))
        XCTAssertTrue(lines[0].contains("test.png"))
    }

    func testKittyRendersBlankRowsAndSequenceAndCachesImageId() {
        let image = PiTUIImage(
            base64Data: "QUJDRA==",
            mimeType: "image/png",
            dimensions: .init(widthPx: 100, heightPx: 100),
            capabilitiesProvider: { .init(images: .kitty) },
            imageIdAllocator: { 1234 }
        )

        let lines = image.render(width: 20)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(image.getImageId(), 1234)
        XCTAssertTrue(lines.last?.contains("\u{001B}_G") == true)
        if lines.count > 1 {
            XCTAssertTrue(lines.last?.contains("\u{001B}[") == true)
            XCTAssertTrue(lines.dropLast().allSatisfy(\.isEmpty))
        }

        // cache path
        let second = image.render(width: 20)
        XCTAssertEqual(lines, second)
        XCTAssertEqual(image.getImageId(), 1234)
    }

    func testITerm2UsesWidthInCharacterUnits() {
        let image = PiTUIImage(
            base64Data: "QUJDRA==",
            mimeType: "image/png",
            dimensions: .init(widthPx: 100, heightPx: 50),
            options: .init(filename: "pic.png"),
            capabilitiesProvider: { .init(images: .iterm2) }
        )

        let lines = image.render(width: 30)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.last?.contains("\u{001B}]1337;File=") == true)
        XCTAssertTrue(lines.last?.contains("width=28ch") == true)
        XCTAssertTrue(lines.last?.contains("name=") == true)
    }

    func testTerminalImageHelpersEncodeAndCalculateRows() {
        let kitty = PiTUITerminalImage.encodeKitty(base64Data: String(repeating: "A", count: 5000), columns: 10, rows: 2, imageId: 77)
        XCTAssertTrue(kitty.contains("a=T"))
        XCTAssertTrue(kitty.contains("i=77"))
        XCTAssertTrue(kitty.contains("m=1"))
        XCTAssertTrue(kitty.contains("m=0"))

        let iterm = PiTUITerminalImage.encodeITerm2(base64Data: "QUJD", width: "10ch", filename: "a.png")
        XCTAssertTrue(iterm.contains("\u{001B}]1337;File="))
        XCTAssertTrue(iterm.contains("width=10ch"))
        XCTAssertTrue(iterm.contains("name="))

        let rows = PiTUITerminalImage.calculateRows(
            imageDimensions: .init(widthPx: 800, heightPx: 600),
            targetWidthCells: 40,
            cellDimensions: .init(widthPx: 10, heightPx: 20)
        )
        XCTAssertGreaterThan(rows, 0)
    }
}
