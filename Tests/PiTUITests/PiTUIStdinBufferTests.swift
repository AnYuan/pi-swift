import Foundation
import XCTest
@testable import PiTUI

final class PiTUIStdinBufferTests: XCTestCase {
    func testSplitsPlainTextIntoSingleCharacterEvents() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("ab你")

        XCTAssertEqual(emitted, ["a", "b", "你"])
    }

    func testBuffersIncompleteCsiSequenceAcrossChunks() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("\u{001B}[")
        XCTAssertTrue(emitted.isEmpty)
        XCTAssertEqual(buffer.getBuffer(), "\u{001B}[")

        buffer.process("A")
        XCTAssertEqual(emitted, ["\u{001B}[A"])
        XCTAssertEqual(buffer.getBuffer(), "")
    }

    func testParsesSgrMouseSequenceOnlyWhenComplete() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("\u{001B}[<35")
        buffer.process(";20")
        XCTAssertTrue(emitted.isEmpty)

        buffer.process(";5m")
        XCTAssertEqual(emitted, ["\u{001B}[<35;20;5m"])
    }

    func testParsesOscSequenceAcrossChunks() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("\u{001B}]0;title")
        XCTAssertTrue(emitted.isEmpty)
        buffer.process("\u{0007}")

        XCTAssertEqual(emitted, ["\u{001B}]0;title\u{0007}"])
    }

    func testEmitsBracketedPasteAsPasteEvent() {
        let buffer = PiTUIStdinBuffer()
        var dataEvents: [String] = []
        var pasteEvents: [String] = []
        buffer.onData { dataEvents.append($0) }
        buffer.onPaste { pasteEvents.append($0) }

        buffer.process("\u{001B}[200~hello\nworld\u{001B}[201~")

        XCTAssertEqual(dataEvents, [])
        XCTAssertEqual(pasteEvents, ["hello\nworld"])
    }

    func testHandlesBracketedPasteInChunksWithDataBeforeAndAfter() {
        let buffer = PiTUIStdinBuffer()
        var dataEvents: [String] = []
        var pasteEvents: [String] = []
        buffer.onData { dataEvents.append($0) }
        buffer.onPaste { pasteEvents.append($0) }

        buffer.process("A\u{001B}[200~pa")
        buffer.process("sted")
        buffer.process("\u{001B}[201~B")

        XCTAssertEqual(dataEvents, ["A", "B"])
        XCTAssertEqual(pasteEvents, ["pasted"])
    }

    func testSingleHighByteBufferConvertsToEscPrefixedMetaSequence() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process(Data([0xE1])) // 225 -> ESC + 97 ('a')

        XCTAssertEqual(emitted, ["\u{001B}a"])
    }

    func testFlushReturnsIncompleteRemainder() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("\u{001B}[")
        XCTAssertTrue(emitted.isEmpty)

        XCTAssertEqual(buffer.flush(), ["\u{001B}["])
        XCTAssertEqual(buffer.getBuffer(), "")
    }

    func testEmptyInputWithEmptyBufferEmitsEmptyDataEventForCompatibility() {
        let buffer = PiTUIStdinBuffer()
        var emitted: [String] = []
        buffer.onData { emitted.append($0) }

        buffer.process("")

        XCTAssertEqual(emitted, [""])
    }
}
