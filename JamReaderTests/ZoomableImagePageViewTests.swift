import UIKit
import XCTest
@testable import JamReader

@MainActor
final class ZoomableImagePageViewTests: XCTestCase {
    func testConfigurationBeforeScrollViewLayoutFitsTheCurrentBounds() {
        let pageView = ZoomableImagePageView(frame: .zero)
        pageView.layoutIfNeeded()
        pageView.frame = CGRect(x: 0, y: 0, width: 400, height: 800)

        pageView.configureContentLayout(
            size: CGSize(width: 100, height: 200),
            fitMode: .page,
            resetZoomScale: true
        )
        pageView.layoutIfNeeded()

        XCTAssertEqual(pageView.contentContainerView.frame.width, 400, accuracy: 0.5)
        XCTAssertEqual(pageView.contentContainerView.frame.height, 800, accuracy: 0.5)
        XCTAssertTrue(pageView.isAtPreferredZoom)
    }

    func testResizingRefitsWithoutAnotherConfiguration() {
        let pageView = makePageView()
        pageView.frame.size = CGSize(width: 800, height: 400)
        pageView.layoutIfNeeded()

        XCTAssertEqual(pageView.contentContainerView.frame.height, 400, accuracy: 0.5)
        XCTAssertEqual(pageView.contentContainerView.frame.width, 400 * 2 / 3, accuracy: 0.5)
        XCTAssertTrue(pageView.isAtPreferredZoom)
    }

    func testResizingPreservesUserZoom() throws {
        let pageView = makePageView()
        let scrollView = try XCTUnwrap(pageView.contentContainerView.superview as? UIScrollView)
        scrollView.zoomScale = scrollView.minimumZoomScale * 2
        let userZoomScale = scrollView.zoomScale

        pageView.frame.size = CGSize(width: 800, height: 400)
        pageView.layoutIfNeeded()

        XCTAssertEqual(scrollView.zoomScale, userZoomScale, accuracy: 0.001)
        XCTAssertEqual(pageView.contentContainerView.frame.height, 6_000 * userZoomScale, accuracy: 0.5)
        XCTAssertFalse(pageView.isAtPreferredZoom)
    }

    func testResizingClampsUserZoomToTheNewMaximum() throws {
        let pageView = makePageView(contentSize: CGSize(width: 100, height: 200))
        let scrollView = try XCTUnwrap(pageView.contentContainerView.superview as? UIScrollView)
        scrollView.zoomScale = 12

        pageView.frame.size = CGSize(width: 100, height: 200)
        pageView.layoutIfNeeded()

        XCTAssertEqual(scrollView.maximumZoomScale, 4, accuracy: 0.001)
        XCTAssertEqual(scrollView.zoomScale, 4, accuracy: 0.001)
        XCTAssertFalse(pageView.isAtPreferredZoom)
    }

    func testUnchangedLayoutAndConfigurationPreserveUserZoom() throws {
        let pageView = makePageView()
        let scrollView = try XCTUnwrap(pageView.contentContainerView.superview as? UIScrollView)
        scrollView.zoomScale = scrollView.minimumZoomScale * 2
        let userZoomScale = scrollView.zoomScale

        pageView.setNeedsLayout()
        pageView.layoutIfNeeded()
        pageView.configureContentLayout(
            size: CGSize(width: 4_000, height: 6_000),
            fitMode: .page,
            resetZoomScale: false
        )

        XCTAssertEqual(scrollView.zoomScale, userZoomScale, accuracy: 0.001)
        XCTAssertFalse(pageView.isAtPreferredZoom)
    }

    func testExplicitResetRestoresPreferredZoom() throws {
        let pageView = makePageView()
        let scrollView = try XCTUnwrap(pageView.contentContainerView.superview as? UIScrollView)
        scrollView.zoomScale = scrollView.minimumZoomScale * 2

        pageView.configureContentLayout(
            size: CGSize(width: 4_000, height: 6_000),
            fitMode: .page,
            resetZoomScale: true
        )

        XCTAssertTrue(pageView.isAtPreferredZoom)
        XCTAssertEqual(scrollView.contentOffset, .zero)
    }

    func testResizingUsesTheConfiguredFitMode() {
        for fitMode in [ReaderFitMode.width, .height, .originalSize] {
            let pageView = makePageView(fitMode: fitMode)
            pageView.frame.size = CGSize(width: 800, height: 400)
            pageView.layoutIfNeeded()

            switch fitMode {
            case .width:
                XCTAssertEqual(pageView.contentContainerView.frame.width, 800, accuracy: 0.5)
            case .height:
                XCTAssertEqual(pageView.contentContainerView.frame.height, 400, accuracy: 0.5)
            case .originalSize:
                XCTAssertEqual(pageView.contentContainerView.frame.height, 6_000, accuracy: 0.5)
            case .page:
                XCTFail("Fit page is covered separately")
            }
        }
    }

    private func makePageView(
        contentSize: CGSize = CGSize(width: 4_000, height: 6_000),
        fitMode: ReaderFitMode = .page
    ) -> ZoomableImagePageView {
        let pageView = ZoomableImagePageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        pageView.layoutIfNeeded()
        pageView.configureContentLayout(size: contentSize, fitMode: fitMode, resetZoomScale: true)
        pageView.layoutIfNeeded()
        return pageView
    }
}
