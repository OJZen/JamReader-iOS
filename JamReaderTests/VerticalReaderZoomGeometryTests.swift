import UIKit
import XCTest
@testable import JamReader

final class VerticalReaderZoomGeometryTests: XCTestCase {
    func testBasePageUsesEntireViewportWidthAndScalesUniformly() {
        XCTAssertEqual(
            VerticalReaderZoomGeometry.pageSize(
                viewportWidth: 1_024,
                aspectRatio: 1.5,
                scale: 1
            ),
            CGSize(width: 1_024, height: 1_536)
        )
        XCTAssertEqual(
            VerticalReaderZoomGeometry.pageSize(
                viewportWidth: 1_024,
                aspectRatio: 1.5,
                scale: 2
            ),
            CGSize(width: 2_048, height: 3_072)
        )
    }

    func testScaleIsClampedAndZoomStateUsesTolerance() {
        XCTAssertEqual(VerticalReaderZoomGeometry.clampedScale(0.5), 1)
        XCTAssertEqual(VerticalReaderZoomGeometry.clampedScale(5), 4)
        XCTAssertFalse(VerticalReaderZoomGeometry.isZoomed(1.005))
        XCTAssertTrue(VerticalReaderZoomGeometry.isZoomed(1.02))
    }

    func testVerticalPageSpacingCanBeRemovedCompletely() {
        XCTAssertEqual(
            VerticalReaderZoomGeometry.lineSpacing(
                viewportWidth: 1_024,
                scale: 2,
                pageSpacingEnabled: true
            ),
            36
        )
        XCTAssertEqual(
            VerticalReaderZoomGeometry.lineSpacing(
                viewportWidth: 1_024,
                scale: 2,
                pageSpacingEnabled: false
            ),
            0
        )
    }

    func testZoomPreservesViewportAnchor() {
        let offset = VerticalReaderZoomGeometry.contentOffset(
            preserving: CGPoint(x: 100, y: 200),
            currentContentOffset: CGPoint(x: 0, y: 500),
            from: 1,
            to: 2,
            contentSize: CGSize(width: 2_000, height: 4_000),
            viewportSize: CGSize(width: 1_000, height: 1_000),
            adjustedInsets: .zero
        )

        XCTAssertEqual(offset.x, 100, accuracy: 0.001)
        XCTAssertEqual(offset.y, 1_200, accuracy: 0.001)
    }

    func testContentOffsetIsClampedAtEveryEdge() {
        let lowerOffset = VerticalReaderZoomGeometry.clampedContentOffset(
            CGPoint(x: -200, y: -300),
            contentSize: CGSize(width: 2_000, height: 3_000),
            viewportSize: CGSize(width: 1_000, height: 1_000),
            adjustedInsets: UIEdgeInsets(top: 10, left: 20, bottom: 30, right: 40)
        )
        let upperOffset = VerticalReaderZoomGeometry.clampedContentOffset(
            CGPoint(x: 2_000, y: 3_000),
            contentSize: CGSize(width: 2_000, height: 3_000),
            viewportSize: CGSize(width: 1_000, height: 1_000),
            adjustedInsets: UIEdgeInsets(top: 10, left: 20, bottom: 30, right: 40)
        )

        XCTAssertEqual(lowerOffset, CGPoint(x: -20, y: -10))
        XCTAssertEqual(upperOffset, CGPoint(x: 1_040, y: 2_030))
    }
}
