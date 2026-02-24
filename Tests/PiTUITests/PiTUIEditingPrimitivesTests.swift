import XCTest
@testable import PiTUI

final class PiTUIEditingPrimitivesTests: XCTestCase {
    private final class Box {
        var values: [Int]
        init(_ values: [Int]) { self.values = values }
    }

    func testUndoStackPushPopClearAndLength() {
        let stack = PiUndoStack<[String]>()

        XCTAssertEqual(stack.length, 0)
        stack.push(["a"])
        stack.push(["b"])
        XCTAssertEqual(stack.length, 2)

        XCTAssertEqual(stack.pop(), ["b"])
        XCTAssertEqual(stack.pop(), ["a"])
        XCTAssertNil(stack.pop())

        stack.push(["c"])
        stack.clear()
        XCTAssertEqual(stack.length, 0)
        XCTAssertNil(stack.pop())
    }

    func testUndoStackUsesCloneClosureOnPush() throws {
        let stack = PiUndoStack<Box> { original in
            Box(original.values)
        }
        let box = Box([1, 2])

        stack.push(box)
        box.values.append(3)

        let snapshot = try XCTUnwrap(stack.pop())
        XCTAssertEqual(snapshot.values, [1, 2])
    }

    func testKillRingPushPeekAndIgnoreEmptyText() {
        let ring = PiKillRing()

        ring.push("", options: .init(prepend: false))
        XCTAssertEqual(ring.length, 0)
        XCTAssertNil(ring.peek())

        ring.push("abc", options: .init(prepend: false))
        XCTAssertEqual(ring.length, 1)
        XCTAssertEqual(ring.peek(), "abc")
    }

    func testKillRingAccumulateAppendAndPrepend() {
        let ring = PiKillRing()

        ring.push("abc", options: .init(prepend: false))
        ring.push("def", options: .init(prepend: false, accumulate: true))
        XCTAssertEqual(ring.peek(), "abcdef")

        ring.push(">>", options: .init(prepend: true, accumulate: true))
        XCTAssertEqual(ring.peek(), ">>abcdef")
        XCTAssertEqual(ring.length, 1)
    }

    func testKillRingRotateCyclesEntries() {
        let ring = PiKillRing()
        ring.push("one", options: .init(prepend: false))
        ring.push("two", options: .init(prepend: false))
        ring.push("three", options: .init(prepend: false))

        XCTAssertEqual(ring.peek(), "three")
        ring.rotate()
        XCTAssertEqual(ring.peek(), "two")
        ring.rotate()
        XCTAssertEqual(ring.peek(), "one")
        ring.rotate()
        XCTAssertEqual(ring.peek(), "three")
    }

    func testKillRingRotateIsNoopForZeroOrOneEntry() {
        let empty = PiKillRing()
        empty.rotate()
        XCTAssertNil(empty.peek())

        let single = PiKillRing()
        single.push("solo", options: .init(prepend: false))
        single.rotate()
        XCTAssertEqual(single.peek(), "solo")
    }
}
