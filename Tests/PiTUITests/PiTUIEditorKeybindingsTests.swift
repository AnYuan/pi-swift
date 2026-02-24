import XCTest
@testable import PiTUI

final class PiTUIEditorKeybindingsTests: XCTestCase {
    override func tearDown() {
        PiTUIEditorKeybindings.set(PiTUIEditorKeybindingsManager())
        super.tearDown()
    }

    func testDefaultBindingsMatchExpectedActions() {
        let kb = PiTUIEditorKeybindingsManager()

        XCTAssertTrue(kb.matches("\u{001B}[D", action: .cursorLeft))
        XCTAssertTrue(kb.matches("\u{0002}", action: .cursorLeft)) // ctrl+b
        XCTAssertTrue(kb.matches("\u{0017}", action: .deleteWordBackward)) // ctrl+w
        XCTAssertTrue(kb.matches("\u{0019}", action: .yank)) // ctrl+y
        XCTAssertTrue(kb.matches("\u{001B}y", action: .yankPop)) // alt+y
    }

    func testCustomConfigOverridesDefaults() {
        let kb = PiTUIEditorKeybindingsManager(config: [.submit: ["escape"]])

        XCTAssertTrue(kb.matches("\u{001B}", action: .submit))
        XCTAssertFalse(kb.matches("\r", action: .submit))
    }

    func testGlobalKeybindingsCanBeReplaced() {
        let custom = PiTUIEditorKeybindingsManager(config: [.selectCancel: ["ctrl+g"]])
        PiTUIEditorKeybindings.set(custom)

        XCTAssertTrue(PiTUIEditorKeybindings.get().matches("\u{0007}", action: .selectCancel))
        XCTAssertFalse(PiTUIEditorKeybindings.get().matches("\u{001B}", action: .selectCancel))
    }
}
