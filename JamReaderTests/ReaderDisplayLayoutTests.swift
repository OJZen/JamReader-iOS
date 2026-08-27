import XCTest
@testable import JamReader

final class ReaderDisplayLayoutTests: XCTestCase {
    func testMangaDefaultsUseRightToLeftPagedSinglePageLayout() {
        let layout = ReaderDisplayLayout(defaultsFor: .manga)

        XCTAssertEqual(layout.pagingMode, .paged)
        XCTAssertEqual(layout.spreadMode, .singlePage)
        XCTAssertEqual(layout.readingDirection, .rightToLeft)
        XCTAssertEqual(layout.fitMode, .page)
    }

    func testWebComicDefaultsUseVerticalContinuousFitWidthLayout() {
        let layout = ReaderDisplayLayout(defaultsFor: .webComic)

        XCTAssertEqual(layout.pagingMode, .verticalContinuous)
        XCTAssertEqual(layout.spreadMode, .singlePage)
        XCTAssertEqual(layout.readingDirection, .leftToRight)
        XCTAssertEqual(layout.fitMode, .width)
    }

    func testNormalizedDisablesDoublePageSpreadWhenUnavailable() {
        let layout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .page
        )

        XCTAssertEqual(layout.normalized(allowingDoublePageSpread: false).spreadMode, .singlePage)
        XCTAssertEqual(layout.normalized(allowingDoublePageSpread: true).spreadMode, .doublePage)
    }

    func testVerticalContinuousAlwaysNormalizesToSinglePageSpread() {
        let layout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: false,
            fitMode: .width
        )

        let normalizedLayout = layout.normalized(allowingDoublePageSpread: true)
        XCTAssertEqual(normalizedLayout.spreadMode, .singlePage)
    }

    func testDoublePageSpreadsCanKeepFirstPageSingle() {
        let layout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .page
        )

        let spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: 5, layout: layout)

        XCTAssertEqual(spreads.map(\.pageIndices), [[0], [1, 2], [3, 4]])
        XCTAssertEqual(ReaderSpreadDescriptor.spreadIndex(containing: 2, in: spreads), 1)
    }

    func testDoublePageSpreadsCanPairFirstAndSecondPages() {
        let layout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: false,
            fitMode: .page
        )

        let spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: 5, layout: layout)

        XCTAssertEqual(spreads.map(\.pageIndices), [[0, 1], [2, 3], [4]])
        XCTAssertEqual(ReaderSpreadDescriptor.spreadIndex(containing: 2, in: spreads), 1)
    }

    func testDisplayPageIndicesReverseForRightToLeftDoublePageSpread() {
        let spread = ReaderSpreadDescriptor(pageIndices: [1, 2])

        XCTAssertEqual(spread.displayPageIndices(for: .leftToRight), [1, 2])
        XCTAssertEqual(spread.displayPageIndices(for: .rightToLeft), [2, 1])
    }
}
