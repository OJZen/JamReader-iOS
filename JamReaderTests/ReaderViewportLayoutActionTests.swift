import XCTest
@testable import JamReader

final class ReaderViewportLayoutActionTests: XCTestCase {
    func testDetachedPageWaitsForTargetViewportInsteadOfResettingOldBounds() {
        let action = ReaderViewportLayoutAction.resolve(
            currentSize: CGSize(width: 1_024, height: 767),
            previousSize: CGSize(width: 1_024, height: 767),
            targetSize: CGSize(width: 744, height: 1_132),
            resetRequired: true
        )

        XCTAssertEqual(action, .waitForTargetViewport)
    }

    func testPageResetsAfterTargetViewportArrives() {
        let action = ReaderViewportLayoutAction.resolve(
            currentSize: CGSize(width: 744, height: 1_132),
            previousSize: CGSize(width: 1_024, height: 767),
            targetSize: CGSize(width: 744, height: 1_132),
            resetRequired: true
        )

        XCTAssertEqual(action, .resetViewport)
    }

    func testUnchangedViewportPreservesUserZoomDuringRehosting() {
        let size = CGSize(width: 744, height: 1_132)
        let action = ReaderViewportLayoutAction.resolve(
            currentSize: size,
            previousSize: size,
            targetSize: nil,
            resetRequired: false
        )

        XCTAssertEqual(action, .preserveViewport)
    }

    func testUnexpectedBoundsChangeStillUsesFallbackReset() {
        let action = ReaderViewportLayoutAction.resolve(
            currentSize: CGSize(width: 900, height: 699),
            previousSize: CGSize(width: 850, height: 699),
            targetSize: nil,
            resetRequired: false
        )

        XCTAssertEqual(action, .resetViewport)
    }
}
