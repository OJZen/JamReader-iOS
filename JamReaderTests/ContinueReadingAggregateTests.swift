import XCTest
@testable import JamReader

/// Batch 5: where continue reading appears, the cross-library aggregate,
/// and quick filters on collection pages.
final class ContinueReadingAggregateTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ContinueReadingAggregateTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - Preference

    func testPlacementDefaultsToLibraryHomeAndPersists() {
        let store = LibraryPreferencesStore(userDefaults: userDefaults)
        XCTAssertEqual(store.loadContinueReadingPlacement(), .libraryHome)

        let changed = expectation(forNotification: .libraryPreferencesDidChange, object: store)
        store.saveContinueReadingPlacement(.insideLibraries)
        wait(for: [changed], timeout: 1)

        let reopened = LibraryPreferencesStore(userDefaults: userDefaults)
        XCTAssertEqual(reopened.loadContinueReadingPlacement(), .insideLibraries)
    }

    func testUnknownPlacementFallsBackToTheDefault() {
        userDefaults.set("sidebar", forKey: LibraryPreferencesStore.continueReadingPlacementStorageKey)
        let store = LibraryPreferencesStore(userDefaults: userDefaults)

        XCTAssertEqual(store.loadContinueReadingPlacement(), .libraryHome)
        XCTAssertEqual(
            userDefaults.string(forKey: LibraryPreferencesStore.continueReadingPlacementStorageKey),
            ContinueReadingPlacement.libraryHome.rawValue
        )
    }

    // MARK: - Aggregate

    func testAggregateOrdersByLastOpenedAndKeysEntriesByLibrary() {
        let comics = makeLibrary("Comics")
        let manga = makeLibrary("Manga")
        let now = Date()
        // Both libraries use row ID 1; the aggregate must keep them apart.
        let rows: [UUID: [LibraryComic]] = [
            comics.id: [makeComic(id: 1, openedAt: now.addingTimeInterval(-60)), makeComic(id: 2, openedAt: nil)],
            manga.id: [makeComic(id: 1, openedAt: now)]
        ]

        let entries = LibraryContinueReadingAggregate.entries(libraries: [comics, manga]) { library, _ in
            rows[library.id] ?? []
        }

        XCTAssertEqual(entries.map(\.library.name), ["Manga", "Comics", "Comics"])
        XCTAssertEqual(entries.map(\.comic.id), [1, 1, 2])
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
    }

    func testAggregateQueriesEachLibraryWithTheLimitAndSkipsFailures() {
        let readable = makeLibrary("Readable")
        let broken = makeLibrary("Broken")
        var requestedLimits: [Int] = []

        let entries = LibraryContinueReadingAggregate.entries(
            libraries: [broken, readable],
            perLibraryLimit: 2
        ) { library, limit in
            requestedLimits.append(limit)
            if library.id == broken.id {
                throw CocoaError(.fileReadNoSuchFile)
            }
            // A loader that ignores the limit is still capped.
            return (1...5).map { self.makeComic(id: Int64($0), openedAt: nil) }
        }

        XCTAssertEqual(requestedLimits, [2, 2])
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.library.id == readable.id })
    }

    func testGroupsFollowLibraryOrderAndReaderStaysInOneLibrary() {
        let comics = makeLibrary("Comics")
        let manga = makeLibrary("Manga")
        let empty = makeLibrary("Empty")
        let entries = [
            ContinueReadingEntry(library: manga, comic: makeComic(id: 7, openedAt: nil)),
            ContinueReadingEntry(library: comics, comic: makeComic(id: 3, openedAt: nil)),
            ContinueReadingEntry(library: manga, comic: makeComic(id: 8, openedAt: nil))
        ]

        let groups = LibraryContinueReadingAggregate.groupedByLibrary(entries, libraryOrder: [comics, empty, manga])
        XCTAssertEqual(groups.map(\.library.name), ["Comics", "Manga"])
        XCTAssertEqual(groups.last?.entries.map(\.comic.id), [7, 8])

        let navigation = LibraryContinueReadingAggregate.navigationComics(for: entries[0], in: entries)
        XCTAssertEqual(navigation.map(\.id), [7, 8])
    }

    // MARK: - Collection filters

    func testCollectionFiltersCombineWithSearch() {
        let comics = [
            makeComic(id: 1, openedAt: nil, fileName: "Harbor 01.cbz"),
            makeComic(id: 2, openedAt: Date(), fileName: "Harbor 02.cbz", currentPage: 4, pageCount: 20),
            makeComic(id: 3, openedAt: Date(), fileName: "Night Owl.cbz", currentPage: 6, pageCount: 20)
        ]

        let inProgress = LibraryCollectionFilterCopy.displayedComics(comics, filter: .reading, searchQuery: "")
        XCTAssertEqual(inProgress.map(\.id), [2, 3])

        let harborInProgress = LibraryCollectionFilterCopy.displayedComics(comics, filter: .reading, searchQuery: "harbor")
        XCTAssertEqual(harborInProgress.map(\.id), [2])

        XCTAssertEqual(
            LibraryCollectionFilterCopy.displayedComics(comics, filter: .all, searchQuery: "").map(\.id),
            [1, 2, 3]
        )
    }

    func testEmptyFilteredResultNamesEveryActiveCondition() {
        XCTAssertNil(LibraryCollectionFilterCopy.emptyResult(collectionTitle: "Favorites", filter: .all, searchQuery: "  "))

        let filterOnly = LibraryCollectionFilterCopy.emptyResult(collectionTitle: "Favorites", filter: .read, searchQuery: "")
        XCTAssertEqual(filterOnly?.description, "No “Read” comics in “Favorites”.")
        XCTAssertEqual(filterOnly?.searchesText, false)

        let both = LibraryCollectionFilterCopy.emptyResult(collectionTitle: "Favorites", filter: .read, searchQuery: " owl ")
        XCTAssertEqual(both?.description, "No “Read” comics in “Favorites” match “owl”.")
        XCTAssertEqual(both?.searchesText, true)

        let searchOnly = LibraryCollectionFilterCopy.emptyResult(collectionTitle: "Favorites", filter: .all, searchQuery: "owl")
        XCTAssertEqual(searchOnly?.description, "No comics in “Favorites” match “owl”.")
    }

    // MARK: - Fixtures

    private func makeLibrary(_ name: String) -> LibraryDescriptor {
        LibraryDescriptor(
            id: UUID(),
            kind: .appManaged,
            name: name,
            rootPath: "/\(name)",
            bookmarkData: Data(),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeComic(
        id: Int64,
        openedAt: Date?,
        fileName: String? = nil,
        currentPage: Int = 1,
        pageCount: Int = 10
    ) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: 1,
            fileName: fileName ?? "Comic \(id).cbz",
            path: "/\(fileName ?? "Comic \(id).cbz")",
            hash: "hash-\(id)",
            title: nil,
            issueNumber: nil,
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: nil,
            bookmarkPageIndices: [],
            read: false,
            hasBeenOpened: openedAt != nil,
            coverSizeRatio: nil,
            lastOpenedAt: openedAt,
            addedAt: nil,
            type: .comic,
            series: nil,
            volume: nil,
            rating: nil,
            isFavorite: false
        )
    }
}
