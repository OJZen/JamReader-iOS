import UIKit
import XCTest
@testable import JamReader

final class ReaderDismissGestureDirectionTests: XCTestCase {
    func testRightDismissAcceptsOnlyDominantPositiveHorizontalMotion() {
        XCTAssertTrue(ReaderDismissGestureDirection.right.accepts(CGPoint(x: 120, y: 40)))
        XCTAssertFalse(ReaderDismissGestureDirection.right.accepts(CGPoint(x: 80, y: 50)))
        XCTAssertFalse(ReaderDismissGestureDirection.right.accepts(CGPoint(x: -120, y: 10)))
        XCTAssertFalse(ReaderDismissGestureDirection.right.accepts(CGPoint(x: 10, y: 120)))
    }

    func testDownDismissAcceptsOnlyDominantPositiveVerticalMotion() {
        XCTAssertTrue(ReaderDismissGestureDirection.down.accepts(CGPoint(x: 40, y: 120)))
        XCTAssertFalse(ReaderDismissGestureDirection.down.accepts(CGPoint(x: 50, y: 80)))
        XCTAssertFalse(ReaderDismissGestureDirection.down.accepts(CGPoint(x: 10, y: -120)))
        XCTAssertFalse(ReaderDismissGestureDirection.down.accepts(CGPoint(x: 120, y: 10)))
    }

    func testDismissDefersToScrollableContentAlongItsAxis() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        scrollView.contentSize = CGSize(width: 300, height: 100)
        XCTAssertTrue(ReaderDismissGestureDirection.right.shouldDefer(to: scrollView))
        XCTAssertFalse(ReaderDismissGestureDirection.down.shouldDefer(to: scrollView))

        scrollView.contentSize = CGSize(width: 100, height: 300)
        XCTAssertFalse(ReaderDismissGestureDirection.right.shouldDefer(to: scrollView))
        XCTAssertTrue(ReaderDismissGestureDirection.down.shouldDefer(to: scrollView))
    }

    func testDismissDefersToZoomedContentRegardlessOfDirection() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let contentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let zoomDelegate = TestZoomScrollViewDelegate(contentView: contentView)
        scrollView.addSubview(contentView)
        scrollView.delegate = zoomDelegate
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.zoomScale = 2

        XCTAssertEqual(scrollView.zoomScale, 2, accuracy: 0.01)
        XCTAssertTrue(ReaderDismissGestureDirection.right.shouldDefer(to: scrollView))
        XCTAssertTrue(ReaderDismissGestureDirection.down.shouldDefer(to: scrollView))
    }

    func testDismissUsesCollectionLayoutAxisInsteadOfCrossAxisInsets() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            collectionViewLayout: layout
        )
        collectionView.contentSize = CGSize(width: 100, height: 300)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        XCTAssertFalse(ReaderDismissGestureDirection.right.shouldDefer(to: collectionView))
        XCTAssertTrue(ReaderDismissGestureDirection.down.shouldDefer(to: collectionView))
    }

    func testDismissOffsetFollowsConfiguredDirection() {
        XCTAssertEqual(
            ReaderDismissGestureDirection.right.offset(for: 80),
            CGSize(width: 80, height: 0)
        )
        XCTAssertEqual(
            ReaderDismissGestureDirection.down.offset(for: 80),
            CGSize(width: 0, height: 80)
        )
    }
}

private final class TestZoomScrollViewDelegate: NSObject, UIScrollViewDelegate {
    private let contentView: UIView

    init(contentView: UIView) {
        self.contentView = contentView
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }
}
