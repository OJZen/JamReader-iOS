import XCTest
@testable import JamReader

final class ReaderHeroGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 400, height: 800)

    func testCoverLandsWhereAFittedPageSits() {
        let frame = ReaderHeroGeometry.landingFrame(
            for: CGSize(width: 200, height: 300),
            in: screen,
            topInset: nil
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 100, width: 400, height: 600))
    }

    func testWideCoverIsLimitedByHeightInALandscapeWindow() {
        let frame = ReaderHeroGeometry.landingFrame(
            for: CGSize(width: 300, height: 400),
            in: CGRect(x: 0, y: 0, width: 800, height: 400),
            topInset: nil
        )

        XCTAssertEqual(frame, CGRect(x: 250, y: 0, width: 300, height: 400))
    }

    func testContinuousReaderLandsTheCoverFullWidthBelowItsInset() {
        let frame = ReaderHeroGeometry.landingFrame(
            for: CGSize(width: 200, height: 300),
            in: screen,
            topInset: 12
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 12, width: 400, height: 600))
    }

    func testContinuousReaderKeepsATallCoverFullWidth() {
        let frame = ReaderHeroGeometry.landingFrame(
            for: CGSize(width: 100, height: 400),
            in: screen,
            topInset: 12
        )

        XCTAssertEqual(frame, CGRect(x: 0, y: 12, width: 400, height: 1600))
    }

    func testCoverWithoutSizeFillsTheReader() {
        let frame = ReaderHeroGeometry.landingFrame(for: .zero, in: screen, topInset: nil)

        XCTAssertEqual(frame, screen)
    }

    func testSnapshotStaysPutWhileTheHeroMatchesThePage() {
        let contentRect = CGRect(x: 0, y: 100, width: 400, height: 600)

        let placement = ReaderHeroGeometry.snapshotPlacement(
            viewportSize: screen.size,
            contentRect: contentRect,
            filling: CGRect(origin: .zero, size: contentRect.size)
        )

        XCTAssertEqual(placement.scale, 1)
        // The hero starts 100 pt down the viewport, so the snapshot sits 100 pt up.
        XCTAssertEqual(placement.center, CGPoint(x: 200, y: 300))
    }

    func testSnapshotKeepsItsProportionsInASmallerCover() {
        let placement = ReaderHeroGeometry.snapshotPlacement(
            viewportSize: screen.size,
            contentRect: CGRect(x: 0, y: 100, width: 400, height: 600),
            filling: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        // The page's shorter side fills the cover and the longer one is clipped.
        XCTAssertEqual(placement.scale, 0.25)
        XCTAssertEqual(placement.center, CGPoint(x: 50, y: 50))
    }

    func testSnapshotCentersThePageRatherThanTheViewport() {
        let placement = ReaderHeroGeometry.snapshotPlacement(
            viewportSize: screen.size,
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
            filling: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(placement.scale, 0.25)
        XCTAssertEqual(placement.center, CGPoint(x: 50, y: 100))
    }

    func testDragProgressStaysBetweenZeroAndOne() {
        XCTAssertEqual(ReaderHeroGeometry.dragProgress(distance: -10), 0)
        XCTAssertEqual(ReaderHeroGeometry.dragProgress(distance: 175), 0.5)
        XCTAssertEqual(ReaderHeroGeometry.dragProgress(distance: 900), 1)
    }

    func testDragStartsExactlyOnThePage() {
        let page = CGRect(x: 0, y: 100, width: 400, height: 600)

        let frame = ReaderHeroGeometry.dragFrame(from: page, offset: .zero, progress: 0)

        XCTAssertEqual(frame, page)
    }

    func testDraggedPageFollowsTheFingerWhileShrinking() {
        let page = CGRect(x: 0, y: 100, width: 400, height: 600)

        let frame = ReaderHeroGeometry.dragFrame(
            from: page,
            offset: CGSize(width: 0, height: 350),
            progress: 1
        )

        XCTAssertEqual(frame.midX, page.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, page.midY + 350, accuracy: 0.001)
        XCTAssertLessThan(frame.width, page.width)
        XCTAssertEqual(frame.width / frame.height, page.width / page.height, accuracy: 0.001)
    }
}
