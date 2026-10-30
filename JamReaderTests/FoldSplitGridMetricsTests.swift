import XCTest
@testable import JamReader

final class FoldSplitGridMetricsTests: XCTestCase {
    func testColumnsAreEvenAndEqualWithTheGutterOnTheFold() throws {
        let metrics = try XCTUnwrap(
            FoldSplitGridMetrics.make(
                containerWidth: 900,
                leadingInset: 16,
                trailingInset: 16,
                foldMinX: 440,
                foldMaxX: 460,
                minimumItemWidth: 120,
                spacing: 12
            )
        )

        XCTAssertEqual(metrics.columns % 2, 0)
        XCTAssertGreaterThanOrEqual(metrics.columns, 2)
        let half = metrics.columns / 2
        let gutterMinX = metrics.columnOrigins[half - 1] + metrics.itemWidth
        let gutterMaxX = metrics.columnOrigins[half]
        XCTAssertEqual((gutterMinX + gutterMaxX) / 2, 450, accuracy: 0.5)
        XCTAssertLessThanOrEqual(gutterMinX, 440)
        XCTAssertGreaterThanOrEqual(gutterMaxX, 460)
        XCTAssertGreaterThanOrEqual(metrics.columnOrigins[0], 16)
        XCTAssertLessThanOrEqual(metrics.columnOrigins.last! + metrics.itemWidth, 884)
    }

    func testOffCentreFoldKeepsTheNarrowSideInsetAndEqualWidths() throws {
        let metrics = try XCTUnwrap(
            FoldSplitGridMetrics.make(
                containerWidth: 900,
                leadingInset: 0,
                trailingInset: 60,
                foldMinX: 440,
                foldMaxX: 460,
                minimumItemWidth: 100,
                spacing: 10
            )
        )

        let half = metrics.columns / 2
        let right = metrics.columnOrigins[half...]
        XCTAssertEqual(right.last! + metrics.itemWidth, 840, accuracy: 1)
        XCTAssertGreaterThan(metrics.columnOrigins[0], 0)
        XCTAssertEqual(metrics.centerGutter, 30, accuracy: 0.5)
    }

    func testOpeningOrClosingOnlyMovesTheGutter() throws {
        let flat = try XCTUnwrap(
            FoldSplitGridMetrics.make(
                containerWidth: 900, leadingInset: 16, trailingInset: 16,
                foldMinX: 450, foldMaxX: 450, minimumItemWidth: 120, spacing: 12
            )
        )
        let folded = try XCTUnwrap(
            FoldSplitGridMetrics.make(
                containerWidth: 900, leadingInset: 16, trailingInset: 16,
                foldMinX: 430, foldMaxX: 470, minimumItemWidth: 120, spacing: 12
            )
        )

        XCTAssertEqual(flat.columns, folded.columns)
    }

    func testNoMetricsWhenTheFoldMissesTheContentOrLeavesNoRoom() {
        XCTAssertNil(
            FoldSplitGridMetrics.make(
                containerWidth: 400, leadingInset: 16, trailingInset: 16,
                foldMinX: 500, foldMaxX: 520, minimumItemWidth: 100, spacing: 12
            )
        )
        XCTAssertNil(
            FoldSplitGridMetrics.make(
                containerWidth: 300, leadingInset: 16, trailingInset: 16,
                foldMinX: 140, foldMaxX: 160, minimumItemWidth: 200, spacing: 12
            )
        )
    }
}
