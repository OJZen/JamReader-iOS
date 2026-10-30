import XCTest
@testable import JamReader

/// Control visibility follows docs/design-system/03-reader.md, "显示面板的控件可见性".
final class ReaderDisplayPanelTests: XCTestCase {
    func testNarrowPagedShowsModeFitAndRotationOnly() {
        let controls = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(pagingMode: .paged, spreadMode: .singlePage),
            supportsImageLayoutControls: true,
            supportsDoublePageSpread: false,
            supportsRotation: true
        )

        XCTAssertTrue(controls.showsReadingMode)
        XCTAssertTrue(controls.showsFitMode)
        XCTAssertTrue(controls.showsRotation)
        XCTAssertFalse(controls.showsSpreadMode)
        XCTAssertFalse(controls.showsSpreadOptions)
        // A single page has no neighbour to space from.
        XCTAssertFalse(controls.showsPageSpacing)
    }

    func testWidePagedShowsSpreadOptionsOnlyForDoublePages() {
        let single = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(pagingMode: .paged, spreadMode: .singlePage),
            supportsImageLayoutControls: true,
            supportsDoublePageSpread: true,
            supportsRotation: true
        )
        XCTAssertTrue(single.showsSpreadMode)
        XCTAssertFalse(single.showsSpreadOptions)

        let double = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(pagingMode: .paged, spreadMode: .doublePage),
            supportsImageLayoutControls: true,
            supportsDoublePageSpread: true,
            supportsRotation: true
        )
        XCTAssertTrue(double.showsSpreadOptions)
        XCTAssertTrue(double.showsPageSpacing)
    }

    func testVerticalShowsModeAndSpacingOnly() {
        let controls = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(pagingMode: .verticalContinuous),
            supportsImageLayoutControls: true,
            supportsDoublePageSpread: true,
            supportsRotation: false
        )

        XCTAssertTrue(controls.showsReadingMode)
        XCTAssertTrue(controls.showsPageSpacing)
        XCTAssertFalse(controls.showsSpreadMode)
        XCTAssertFalse(controls.showsFitMode)
        XCTAssertFalse(controls.showsRotation)
        XCTAssertEqual(
            controls.footnote,
            String(localized: "These settings become the default for comics you open later.")
        )
    }

    func testRenderedDocumentShowsRotationOnly() {
        let controls = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(),
            supportsImageLayoutControls: false,
            supportsDoublePageSpread: true,
            supportsRotation: true
        )

        XCTAssertFalse(controls.isEmpty)
        XCTAssertFalse(controls.showsReadingMode)
        XCTAssertFalse(controls.showsFitMode)
        XCTAssertTrue(controls.showsRotation)
        XCTAssertNil(controls.footnote)
    }

    func testDocumentWithoutDisplaySettingsHidesPanel() {
        let controls = ReaderDisplayPanelControls(
            layout: ReaderDisplayLayout(),
            supportsImageLayoutControls: false,
            supportsDoublePageSpread: false,
            supportsRotation: false
        )

        XCTAssertTrue(controls.isEmpty)
    }

    /// A compact window (iPhone, iPhone Duo's outer screen) shows single pages
    /// without rewriting the saved double-page layout; a regular window gets it back.
    func testCompactWindowKeepsSavedDoublePageLayout() {
        let saved = ReaderDisplayLayout(
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: false
        )

        let compact = saved.normalized(allowingDoublePageSpread: false)
        XCTAssertEqual(compact.spreadMode, .singlePage)
        XCTAssertEqual(compact.readingDirection, .leftToRight)
        XCTAssertFalse(compact.coverAsSinglePage)
        XCTAssertEqual(saved.normalized(allowingDoublePageSpread: true), saved)

        let controls = ReaderDisplayPanelControls(
            layout: compact,
            supportsImageLayoutControls: true,
            supportsDoublePageSpread: false,
            supportsRotation: true
        )
        XCTAssertFalse(controls.showsSpreadMode)
        XCTAssertFalse(controls.showsSpreadOptions)
    }

    func testBookmarkLimitBlocksOnlyNewPages() {
        let bookmarks = [1, 4, 9]

        XCTAssertFalse(ReaderBookmarkSupport.canToggle(bookmarks, at: 12, maximumCount: 3))
        XCTAssertTrue(ReaderBookmarkSupport.canToggle(bookmarks, at: 4, maximumCount: 3))
        XCTAssertTrue(ReaderBookmarkSupport.canToggle([1, 4], at: 12, maximumCount: 3))
        XCTAssertTrue(ReaderBookmarkSupport.canToggle(bookmarks, at: 12, maximumCount: nil))
    }
}
