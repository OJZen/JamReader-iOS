import XCTest
@testable import JamReader

final class ReaderPreferenceStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testReaderLayoutDefaultsFollowFileType() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadLayout(for: .manga), ReaderDisplayLayout(defaultsFor: .manga))
        XCTAssertEqual(store.loadLayout(for: .webComic), ReaderDisplayLayout(defaultsFor: .webComic))
        XCTAssertEqual(store.loadLayout(for: .comic), ReaderDisplayLayout(defaultsFor: .comic))
    }

    func testReaderLayoutRoundTripsByPreferenceScope() {
        let userDefaults = makeUserDefaults()
        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
        let mangaLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .doublePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: false,
            fitMode: .height
        )
        let comicLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .singlePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: true,
            fitMode: .width
        )
        let webcomicLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .width
        )

        store.saveLayout(mangaLayout, for: .manga)
        store.saveLayout(comicLayout, for: .comic)
        store.saveLayout(webcomicLayout, for: .webComic)

        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .manga), mangaLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .yonkoma), mangaLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .comic), comicLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .westernManga), comicLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .webComic), webcomicLayout)
    }

    func testLegacyComicPreferencesMigrateToIndependentWebcomicScope() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(ReaderPagingMode.paged.rawValue, forKey: "reader.layout.comic.pagingMode")
        userDefaults.set(ReaderSpreadMode.doublePage.rawValue, forKey: "reader.layout.comic.spreadMode")
        userDefaults.set(ReaderReadingDirection.rightToLeft.rawValue, forKey: "reader.layout.comic.readingDirection")
        userDefaults.set(ReaderFitMode.height.rawValue, forKey: "reader.layout.comic.fitMode")
        userDefaults.set(false, forKey: "reader.layout.comic.coverAsSinglePage")

        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)

        XCTAssertEqual(
            store.loadLayout(for: .webComic),
            ReaderDisplayLayout(
                pagingMode: .paged,
                spreadMode: .doublePage,
                readingDirection: .rightToLeft,
                coverAsSinglePage: false,
                fitMode: .height
            )
        )

        store.saveLayout(ReaderDisplayLayout(defaultsFor: .comic), for: .comic)

        XCTAssertEqual(store.loadLayout(for: .webComic).spreadMode, .doublePage)
        XCTAssertEqual(store.loadLayout(for: .webComic).readingDirection, .rightToLeft)
    }

    func testResetReaderLayoutRemovesStoredValuesForOnlyThatScope() {
        let userDefaults = makeUserDefaults()
        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
        let customComicLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        let customMangaLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .width
        )
        store.saveLayout(customComicLayout, for: .comic)
        store.saveLayout(customMangaLayout, for: .manga)

        store.resetLayout(for: .comic)

        XCTAssertEqual(store.loadLayout(for: .comic), ReaderDisplayLayout(defaultsFor: .comic))
        XCTAssertEqual(store.loadLayout(for: .manga), customMangaLayout)
    }

    func testInvalidReaderLayoutFieldFallsBackWithoutDiscardingValidFields() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("invalid", forKey: "reader.layout.manga.pagingMode")
        userDefaults.set(ReaderFitMode.height.rawValue, forKey: "reader.layout.manga.fitMode")

        let layout = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
            .loadLayout(for: .manga)

        XCTAssertEqual(layout.pagingMode, ReaderDisplayLayout(defaultsFor: .manga).pagingMode)
        XCTAssertEqual(layout.fitMode, .height)
    }

    func testReaderLayoutNotificationOnlyPostsForPersistedChanges() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())
        var notifiedTypes: [Int] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .readerLayoutPreferencesDidChange,
            object: store,
            queue: nil
        ) { notification in
            if let type = notification.userInfo?["type"] as? Int {
                notifiedTypes.append(type)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let layout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        store.saveLayout(layout, for: .comic)
        store.saveLayout(layout, for: .comic)

        var rotatedLayout = layout
        rotatedLayout.rotation = .degrees90
        store.saveLayout(rotatedLayout, for: .comic)

        XCTAssertEqual(notifiedTypes, [LibraryFileType.comic.rawValue])
    }

    func testResetReaderLayoutOnlyNotifiesWhenStoredValuesExist() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .readerLayoutPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.resetLayout(for: .comic)
        store.saveLayout(
            ReaderDisplayLayout(
                pagingMode: .paged,
                spreadMode: .doublePage,
                readingDirection: .leftToRight,
                coverAsSinglePage: true,
                fitMode: .page
            ),
            for: .comic
        )
        store.resetLayout(for: .comic)
        store.resetLayout(for: .comic)

        XCTAssertEqual(notificationCount, 2)
    }

    func testSettingsSnapshotReaderRefreshOnlyChangesReaderFields() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())
        let comicLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        store.saveLayout(comicLayout, for: .comic)

        var snapshot = SettingsSnapshot.empty
        snapshot.recentWindow = .ninetyDays
        snapshot.localLibraryCount = 42
        snapshot.reloadReaderPreferences(preferencesStore: store)

        XCTAssertEqual(snapshot.comicLayout, comicLayout)
        XCTAssertEqual(snapshot.recentWindow, .ninetyDays)
        XCTAssertEqual(snapshot.localLibraryCount, 42)
    }

    func testEPUBReadingLocationTrimsAndPersistsLocation() {
        let userDefaults = makeUserDefaults()
        let store = EPUBReadingLocationStore(defaults: userDefaults)
        let document = makeEBookDocument(documentID: "book-a")

        store.saveLocation("  epubcfi(/6/2!/4/1:0)  ", for: document)

        XCTAssertEqual(
            EPUBReadingLocationStore(defaults: userDefaults).location(for: document),
            "epubcfi(/6/2!/4/1:0)"
        )
    }

    func testEPUBReadingLocationIsScopedByDocumentIDAndClearsEmptyLocation() {
        let userDefaults = makeUserDefaults()
        let store = EPUBReadingLocationStore(defaults: userDefaults)
        let firstDocument = makeEBookDocument(documentID: "book-a")
        let secondDocument = makeEBookDocument(documentID: "book-b")

        store.saveLocation("chapter-1", for: firstDocument)
        store.saveLocation("chapter-2", for: secondDocument)
        store.saveLocation("  ", for: firstDocument)

        let reloadedStore = EPUBReadingLocationStore(defaults: userDefaults)
        XCTAssertNil(reloadedStore.location(for: firstDocument))
        XCTAssertEqual(reloadedStore.location(for: secondDocument), "chapter-2")
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ReaderPreferenceStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func makeEBookDocument(documentID: String) -> EBookComicDocument {
        EBookComicDocument(
            url: URL(fileURLWithPath: "/tmp/\(documentID).epub"),
            fileExtension: "epub",
            readerKind: .epubJS,
            documentID: documentID
        )
    }
}
