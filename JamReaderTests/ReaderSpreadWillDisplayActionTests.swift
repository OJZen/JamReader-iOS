import XCTest
@testable import JamReader

final class ReaderSpreadWillDisplayActionTests: XCTestCase {
    func testCurrentSpreadPreservesViewportWhenCanceledSwipeReturns() {
        let action = ReaderSpreadWillDisplayAction.resolve(
            displayedSpreadIndex: 4,
            currentSpreadIndex: 4,
            animatedTransitionTargetSpreadIndex: nil
        )

        XCTAssertEqual(action, .preserveCurrentViewport)
    }

    func testNeighborSpreadPreparesForManualPageTurn() {
        let action = ReaderSpreadWillDisplayAction.resolve(
            displayedSpreadIndex: 5,
            currentSpreadIndex: 4,
            animatedTransitionTargetSpreadIndex: nil
        )

        XCTAssertEqual(action, .prepareForPresentation)
    }

    func testAnimatedTargetPrewarmsAfterCurrentIndexAdvances() {
        let action = ReaderSpreadWillDisplayAction.resolve(
            displayedSpreadIndex: 5,
            currentSpreadIndex: 5,
            animatedTransitionTargetSpreadIndex: 5
        )

        XCTAssertEqual(action, .prewarmAnimatedTarget)
    }
}
