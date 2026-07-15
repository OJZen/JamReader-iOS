import UIKit
import XCTest
@testable import JamReader

@MainActor
final class RootOverlayLayoutTests: XCTestCase {
    func testPassthroughViewOnlyCapturesHostedContentBounds() {
        let overlayView = PassthroughOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let hostedContent = UIView(frame: CGRect(x: 20, y: 640, width: 350, height: 160))
        overlayView.addSubview(hostedContent)

        XCTAssertNil(overlayView.hitTest(CGPoint(x: 195, y: 200), with: nil))
        XCTAssertTrue(
            overlayView.hitTest(CGPoint(x: 195, y: 700), with: nil) === hostedContent
        )
    }

    func testOverlayContentUsesIntrinsicHeightAndCapsRegularWidth() {
        let rootController = RootOverlayWindowController()
        rootController.loadViewIfNeeded()
        rootController.view.frame = CGRect(x: 0, y: 0, width: 1_024, height: 1_366)

        let contentController = UIViewController()
        contentController.view = IntrinsicOverlayContentView(height: 180)
        rootController.embed(contentController, bottomOffset: 49)
        rootController.view.layoutIfNeeded()

        XCTAssertEqual(contentController.view.frame.width, AppLayout.overlayMaxWidth, accuracy: 0.5)
        XCTAssertEqual(contentController.view.frame.height, 180, accuracy: 0.5)
        XCTAssertEqual(
            contentController.view.frame.maxY,
            rootController.view.safeAreaLayoutGuide.layoutFrame.maxY - 49,
            accuracy: 0.5
        )
    }
}

private final class IntrinsicOverlayContentView: UIView {
    private let height: CGFloat

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}
