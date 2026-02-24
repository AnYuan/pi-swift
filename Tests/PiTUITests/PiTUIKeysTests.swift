import XCTest
@testable import PiTUI

final class PiTUIKeysTests: XCTestCase {
    override func tearDown() {
        PiTUIKeys.setKittyProtocolActive(false)
        super.tearDown()
    }

    func testParsesLegacyAndSS3ArrowKeys() {
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}[A"), "up")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}[B"), "down")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}[C"), "right")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}[D"), "left")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}OA"), "up")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}OD"), "left")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}OH"), "home")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}OF"), "end")
    }

    func testParsesPrintableAndCommonSpecialKeys() {
        XCTAssertEqual(PiTUIKeys.parseKey("a"), "a")
        XCTAssertEqual(PiTUIKeys.parseKey("A"), "shift+a")
        XCTAssertEqual(PiTUIKeys.parseKey("\r"), "enter")
        XCTAssertEqual(PiTUIKeys.parseKey("\t"), "tab")
        XCTAssertEqual(PiTUIKeys.parseKey(" "), "space")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{007F}"), "backspace")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}"), "escape")
    }

    func testParsesLegacyCtrlKeysAndSymbols() {
        XCTAssertEqual(PiTUIKeys.parseKey("\u{0003}"), "ctrl+c")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{0004}"), "ctrl+d")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{0000}"), "ctrl+space")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001C}"), "ctrl+\\")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001D}"), "ctrl+]")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001F}"), "ctrl+-")
    }

    func testParsesLegacyAltSequencesWhenKittyInactive() {
        PiTUIKeys.setKittyProtocolActive(false)

        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}a"), "alt+a")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}A"), "alt+shift+a")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B} "), "alt+space")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}\u{0008}"), "alt+backspace")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}\u{0003}"), "ctrl+alt+c")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}B"), "alt+left")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}F"), "alt+right")
    }

    func testKittyModeDisablesMostLegacyAltPrefixedSequences() {
        PiTUIKeys.setKittyProtocolActive(true)

        XCTAssertNil(PiTUIKeys.parseKey("\u{001B}a"))
        XCTAssertNil(PiTUIKeys.parseKey("\u{001B}\u{0003}"))
        XCTAssertNil(PiTUIKeys.parseKey("\u{001B}B"))
        XCTAssertEqual(PiTUIKeys.parseKey("\n"), "shift+enter")
        XCTAssertEqual(PiTUIKeys.parseKey("\u{001B}\u{0008}"), "alt+backspace")
    }

    func testMatchesKeySupportsAliasesAndModifierOrdering() {
        XCTAssertTrue(PiTUIKeys.matchesKey("\u{001B}", "esc"))
        XCTAssertTrue(PiTUIKeys.matchesKey("\r", "return"))
        XCTAssertTrue(PiTUIKeys.matchesKey("\u{0003}", "ctrl+c"))
        XCTAssertTrue(PiTUIKeys.matchesKey("\u{001B}\u{0003}", "alt+ctrl+c"))
        XCTAssertTrue(PiTUIKeys.matchesKey("\u{001F}", "ctrl+_"))
        XCTAssertFalse(PiTUIKeys.matchesKey("\u{0003}", "ctrl+d"))
    }
}
