import XCTest
@testable import PiTUI

final class PiTUITerminalImageTests: XCTestCase {
    func testDetectsITerm2ImageSequencesInDifferentPositions() {
        XCTAssertTrue(PiTUITerminalImage.isImageLine("\u{001B}]1337;File=size=100,100;inline=1:data==\u{0007}"))
        XCTAssertTrue(PiTUITerminalImage.isImageLine("prefix \u{001B}]1337;File=inline=1:data==\u{0007} suffix"))
        XCTAssertTrue(PiTUITerminalImage.isImageLine("end \u{001B}]1337;File=:\u{0007}"))
    }

    func testDetectsKittyImageSequencesInDifferentPositions() {
        XCTAssertTrue(PiTUITerminalImage.isImageLine("\u{001B}_Ga=T,f=100;data...\u{001B}\\"))
        XCTAssertTrue(PiTUITerminalImage.isImageLine("Output: \u{001B}_Ga=T;data...\u{001B}\\\u{001B}_Gm=1;\u{001B}\\"))
        XCTAssertTrue(PiTUITerminalImage.isImageLine("  \u{001B}_Ga=T...\u{001B}\\  "))
    }

    func testDetectsImageSequencesInVeryLongLine() {
        let longLine = "Text " + "\u{001B}]1337;File=inline=1:" + String(repeating: "A", count: 300_000)
        XCTAssertTrue(PiTUITerminalImage.isImageLine(longLine))
    }

    func testDoesNotDetectPlainTextOrNormalANSI() {
        XCTAssertFalse(PiTUITerminalImage.isImageLine(""))
        XCTAssertFalse(PiTUITerminalImage.isImageLine("plain text"))
        XCTAssertFalse(PiTUITerminalImage.isImageLine("\u{001B}[31mRed text\u{001B}[0m"))
        XCTAssertFalse(PiTUITerminalImage.isImageLine("Some text with ]1337;File but missing ESC"))
        XCTAssertFalse(PiTUITerminalImage.isImageLine("Some text with _G but missing ESC"))
    }

    func testDetectsMixedImageProtocolsWithANSIText() {
        let line = "\u{001B}[31mError \u{001B}]1337;File=inline=1:data==\u{0007} then \u{001B}_Ga=T;data\u{001B}\\\u{001B}[0m"
        XCTAssertTrue(PiTUITerminalImage.isImageLine(line))
    }
}
