import XCTest
@testable import PiTUI

final class PiTUIOverlayLayoutTests: XCTestCase {
    func testDefaultCenteredLayoutUsesClampedWidth() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: nil,
            overlayHeight: 4,
            termWidth: 100,
            termHeight: 24
        )

        XCTAssertEqual(resolved.width, 80)
        XCTAssertEqual(resolved.row, 10) // (24 - 4) / 2
        XCTAssertEqual(resolved.col, 10) // (100 - 80) / 2
        XCTAssertNil(resolved.maxHeight)
    }

    func testWidthPercentAndMinWidthAreResolvedAndClamped() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: .init(width: .percent(10), minWidth: 30),
            overlayHeight: 2,
            termWidth: 100,
            termHeight: 20
        )

        XCTAssertEqual(resolved.width, 30)
    }

    func testAnchorAndOffsetsRespectMarginsAndClamping() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: .init(
                width: .absolute(10),
                anchor: .bottomRight,
                offsetX: 5,
                offsetY: 5,
                margin: .uniform(2)
            ),
            overlayHeight: 3,
            termWidth: 40,
            termHeight: 12
        )

        XCTAssertEqual(resolved.col, 28) // clamped within margins
        XCTAssertEqual(resolved.row, 7)  // clamped within margins
    }

    func testPercentRowAndColUseRemainingSpaceAfterOverlaySize() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: .init(
                width: .absolute(10),
                row: .percent(50),
                col: .percent(50)
            ),
            overlayHeight: 4,
            termWidth: 40,
            termHeight: 20
        )

        XCTAssertEqual(resolved.col, 15) // maxCol=30 => 50%
        XCTAssertEqual(resolved.row, 8)  // maxRow=16 => 50%
    }

    func testMaxHeightPercentIsReturnedAndClamped() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: .init(maxHeight: .percent(50), margin: .edges(.init(top: 2, bottom: 2))),
            overlayHeight: 20,
            termWidth: 80,
            termHeight: 20
        )

        XCTAssertEqual(resolved.maxHeight, 10) // 50% of termHeight, then <= availHeight(16)
        XCTAssertEqual(resolved.row, 5) // centered using effectiveHeight = 10 within availHeight 16 + marginTop 2
    }

    func testNegativeMarginsAreClampedToZeroViaEdgesInput() {
        let resolved = PiTUIOverlayLayoutPlanner.resolve(
            options: .init(width: .absolute(10), margin: .edges(.init(top: -5, left: -3))),
            overlayHeight: 2,
            termWidth: 20,
            termHeight: 10
        )

        XCTAssertEqual(resolved.col, 5) // centered in full width due clamped negative margins
        XCTAssertEqual(resolved.row, 4)
    }
}
