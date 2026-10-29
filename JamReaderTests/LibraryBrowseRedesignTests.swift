import XCTest
@testable import JamReader

/// Library page behavior introduced by the batch 2 redesign.
final class LibraryBrowseRedesignTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        harnesses.forEach { $0.remove() }
        harnesses.removeAll()
        super.tearDown()
    }

    func testFolderContentListsAncestorsForTheBreadcrumb() throws {
        let harness = try LibraryDatabaseTestHarness.make(testName: #function)
        harnesses.append(harness)
        try harness.writeFile("Marvel/Short Stories/Issue 01.cbz")

        let databaseURL = try harness.databaseURL
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL
        )

        let reader = harness.makeReader()
        let root = try reader.loadFolderContent(databaseURL: databaseURL)
        XCTAssertTrue(root.ancestors.isEmpty)

        let marvel = try XCTUnwrap(root.subfolders.first { $0.displayName == "Marvel" })
        let marvelContent = try reader.loadFolderContent(databaseURL: databaseURL, folderID: marvel.id)
        XCTAssertEqual(marvelContent.ancestors.count, 1)
        XCTAssertTrue(try XCTUnwrap(marvelContent.ancestors.first).isRoot)

        let shortStories = try XCTUnwrap(marvelContent.subfolders.first)
        let deepest = try reader.loadFolderContent(databaseURL: databaseURL, folderID: shortStories.id)
        XCTAssertEqual(deepest.ancestors.map(\.id), [root.folder.id, marvel.id])
        XCTAssertEqual(deepest.folder.displayName, "Short Stories")
    }

    func testQuickFiltersSeparateUnreadReadingAndRead() {
        let unread = makeComic(id: 1)
        let reading = makeComic(id: 2, currentPage: 5, pageCount: 20, hasBeenOpened: true)
        let finished = makeComic(id: 3, currentPage: 20, pageCount: 20, read: true, hasBeenOpened: true)
        let bookmarked = makeComic(id: 4, bookmarks: [3])
        let comics = [unread, reading, finished, bookmarked]

        XCTAssertEqual(comics.filter(LibraryComicQuickFilter.all.matches).map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(comics.filter(LibraryComicQuickFilter.unread.matches).map(\.id), [1, 4])
        XCTAssertEqual(comics.filter(LibraryComicQuickFilter.reading.matches).map(\.id), [2])
        XCTAssertEqual(comics.filter(LibraryComicQuickFilter.read.matches).map(\.id), [3])
        XCTAssertEqual(comics.filter(LibraryComicQuickFilter.bookmarked.matches).map(\.id), [4])
    }

    func testCoverStatusNamesOneStateAndOnlyReadingShowsProgress() {
        XCTAssertEqual(makeComic(id: 1).coverStatusText, "Unread")
        XCTAssertNil(makeComic(id: 1).readingFraction)

        let reading = makeComic(id: 2, currentPage: 21, pageCount: 50, hasBeenOpened: true)
        XCTAssertEqual(reading.coverStatusText, "Read to 42%")
        XCTAssertEqual(try XCTUnwrap(reading.readingFraction), 0.42, accuracy: 0.001)

        let finished = makeComic(id: 3, currentPage: 50, pageCount: 50, read: true, hasBeenOpened: true)
        XCTAssertEqual(finished.coverStatusText, "Read")
        XCTAssertNil(finished.readingFraction)
    }

    func testImportResultBarStaysUntilClosedWhenItemsWereSkippedOrFailed() {
        let clean = makeImportResult(imported: 3)
        XCTAssertEqual(clean.taskBannerContent.phase, .succeeded)
        XCTAssertEqual(clean.taskBannerContent.detail, "Imported Comics · 3 imported")

        let partial = makeImportResult(imported: 2, unsupported: ["notes.txt"], failed: ["Broken.cbz"])
        XCTAssertEqual(partial.taskBannerContent.phase, .needsAttention)
        XCTAssertEqual(
            partial.taskBannerContent.detail,
            "Imported Comics · 2 imported · 1 unsupported · 1 failed"
        )
    }

    func testLibraryKindsUseDistinctTilesAndSymbols() {
        XCTAssertEqual(LibraryKind.appManaged.systemImageName, "books.vertical")
        XCTAssertEqual(LibraryKind.importedComics.systemImageName, "tray")
        XCTAssertTrue(["folder.badge.link", "folder"].contains(LibraryKind.linkedFolder.systemImageName))
        XCTAssertEqual(LibrarySpecialCollectionKind.recent.collectionSystemImageName, "sparkles")
    }

    func testTagsSortByNameOrCountWithNameAsTieBreaker() {
        let tags = [
            makeTag(id: 1, name: "Mystery", count: 2),
            makeTag(id: 2, name: "action", count: 5),
            makeTag(id: 3, name: "Classics", count: 2)
        ]

        XCTAssertEqual(tags.sorted(by: .name).map(\.id), [2, 3, 1])
        XCTAssertEqual(tags.sorted(by: .comicCountDescending).map(\.id), [2, 3, 1])
        XCTAssertEqual(tags.sorted(by: .comicCountAscending).map(\.id), [3, 1, 2])
    }

    private func makeTag(id: Int64, name: String, count: Int) -> LibraryOrganizationCollection {
        LibraryOrganizationCollection(
            id: id,
            name: name,
            type: .label,
            comicCount: count,
            isAssigned: false,
            labelColor: .blue
        )
    }

    private func makeImportResult(
        imported: Int,
        unsupported: [String] = [],
        failed: [String] = []
    ) -> ImportedComicsImportResult {
        ImportedComicsImportResult(
            importedDestinationID: UUID(),
            importedDestinationName: "Imported Comics",
            importedDestinationDisplayName: "Imported Comics",
            createdLibrary: false,
            importedComicCount: imported,
            scanSummary: nil,
            scanErrorMessage: nil,
            unsupportedItemNames: unsupported,
            failedItemNames: failed
        )
    }

    private func makeComic(
        id: Int64,
        currentPage: Int = 0,
        pageCount: Int? = nil,
        read: Bool = false,
        hasBeenOpened: Bool = false,
        bookmarks: [Int] = []
    ) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: 1,
            fileName: "Comic \(id).cbz",
            path: "/Comic \(id).cbz",
            hash: "hash-\(id)",
            title: nil,
            issueNumber: nil,
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: nil,
            bookmarkPageIndices: bookmarks,
            read: read,
            hasBeenOpened: hasBeenOpened,
            coverSizeRatio: nil,
            lastOpenedAt: nil,
            addedAt: nil,
            type: .comic,
            series: nil,
            volume: nil,
            rating: nil,
            isFavorite: false
        )
    }
}
