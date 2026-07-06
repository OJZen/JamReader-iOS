import XCTest
@testable import JamReader

final class ComicPageNameSorterTests: XCTestCase {
    func testSupportedImagePathAcceptsKnownImageExtensionsCaseInsensitively() {
        XCTAssertTrue(ComicPageNameSorter.isSupportedImagePath("chapter/001.JPG"))
        XCTAssertTrue(ComicPageNameSorter.isSupportedImagePath("chapter/002.webp"))
        XCTAssertTrue(ComicPageNameSorter.isSupportedImagePath("chapter/003.GIF"))
    }

    func testSupportedImagePathRejectsEmptyAndMacOSXPaths() {
        XCTAssertFalse(ComicPageNameSorter.isSupportedImagePath(""))
        XCTAssertFalse(ComicPageNameSorter.isSupportedImagePath("   "))
        XCTAssertFalse(ComicPageNameSorter.isSupportedImagePath("__MACOSX/cover.jpg"))
        XCTAssertFalse(ComicPageNameSorter.isSupportedImagePath("chapter/readme.txt"))
    }

    func testSortedPageNamesUsesNaturalOrdering() {
        let sorted = ComicPageNameSorter.sortedPageNames([
            "chapter/page 10.jpg",
            "chapter/page 2.jpg",
            "chapter/page 1.jpg"
        ])

        XCTAssertEqual(sorted, [
            "chapter/page 1.jpg",
            "chapter/page 2.jpg",
            "chapter/page 10.jpg"
        ])
    }

    func testLargePageSetKeepsNaturalOrdering() {
        let pageNames = (1...1_001).reversed().map { "page \($0).jpg" }
        let sorted = ComicPageNameSorter.sortedPageNames(pageNames)

        XCTAssertEqual(sorted.first, "page 1.jpg")
        XCTAssertEqual(sorted.last, "page 1001.jpg")
    }
}
