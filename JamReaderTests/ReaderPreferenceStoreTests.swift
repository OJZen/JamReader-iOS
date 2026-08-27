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

    func testReaderLayoutUsesOneSharedDefault() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadLayout(), ReaderDisplayLayout())
    }

    func testReaderLayoutRoundTripsThroughSharedScope() {
        let userDefaults = makeUserDefaults()
        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
        let layout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )

        store.saveLayout(layout)

        XCTAssertEqual(
            ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(),
            layout
        )
    }

    func testSingleLegacyProfileMigratesToSharedLayout() {
        let userDefaults = makeUserDefaults()
        let legacyLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .width
        )
        setStoredLayout(legacyLayout, scope: "manga", userDefaults: userDefaults)

        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)

        XCTAssertEqual(store.loadLayout(), legacyLayout)
        XCTAssertEqual(
            userDefaults.string(forKey: "reader.layout.shared.pagingMode"),
            ReaderPagingMode.verticalContinuous.rawValue
        )

        userDefaults.set(
            ReaderPagingMode.paged.rawValue,
            forKey: "reader.layout.manga.pagingMode"
        )

        XCTAssertEqual(
            ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(),
            legacyLayout
        )
    }

    func testConflictingLegacyProfilesPreferFormerGeneralComicProfile() {
        let userDefaults = makeUserDefaults()
        let comicLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        let mangaLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .width
        )
        setStoredLayout(mangaLayout, scope: "manga", userDefaults: userDefaults)
        setStoredLayout(comicLayout, scope: "comic", userDefaults: userDefaults)

        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)

        XCTAssertEqual(store.loadLayout(), comicLayout)
    }

    func testMigrationPrefersTheMostCompleteLegacyProfile() {
        let userDefaults = makeUserDefaults()
        let mangaLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .width
        )
        userDefaults.set(
            ReaderPagingMode.paged.rawValue,
            forKey: "reader.layout.comic.pagingMode"
        )
        setStoredLayout(mangaLayout, scope: "manga", userDefaults: userDefaults)

        XCTAssertEqual(
            ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(),
            mangaLayout
        )
    }

    func testExistingSharedLayoutWinsOverLegacyProfiles() {
        let userDefaults = makeUserDefaults()
        let sharedLayout = ReaderDisplayLayout(
            pagingMode: .verticalContinuous,
            spreadMode: .singlePage,
            readingDirection: .leftToRight,
            coverAsSinglePage: true,
            fitMode: .width
        )
        let legacyLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        setStoredLayout(sharedLayout, scope: "shared", userDefaults: userDefaults)
        setStoredLayout(legacyLayout, scope: "comic", userDefaults: userDefaults)

        XCTAssertEqual(
            ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(),
            sharedLayout
        )
    }

    func testResetReaderLayoutRemovesSharedStoredValues() {
        let userDefaults = makeUserDefaults()
        let store = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
        store.saveLayout(
            ReaderDisplayLayout(
                pagingMode: .verticalContinuous,
                spreadMode: .singlePage,
                readingDirection: .rightToLeft,
                coverAsSinglePage: false,
                fitMode: .width
            )
        )

        store.resetLayout()

        XCTAssertEqual(store.loadLayout(), ReaderDisplayLayout())
        XCTAssertNil(userDefaults.object(forKey: "reader.layout.shared.pagingMode"))
    }

    func testInvalidReaderLayoutFieldFallsBackWithoutDiscardingValidFields() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("invalid", forKey: "reader.layout.shared.pagingMode")
        userDefaults.set(ReaderFitMode.height.rawValue, forKey: "reader.layout.shared.fitMode")

        let layout = ReaderLayoutPreferencesStore(userDefaults: userDefaults)
            .loadLayout()

        XCTAssertEqual(layout.pagingMode, ReaderDisplayLayout().pagingMode)
        XCTAssertEqual(layout.fitMode, .height)
    }

    func testReaderLayoutNotificationOnlyPostsForPersistedChanges() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())
        var notifiedScopes: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .readerLayoutPreferencesDidChange,
            object: store,
            queue: nil
        ) { notification in
            if let scope = notification.userInfo?["scope"] as? String {
                notifiedScopes.append(scope)
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
        store.saveLayout(layout)
        store.saveLayout(layout)

        var rotatedLayout = layout
        rotatedLayout.rotation = .degrees90
        store.saveLayout(rotatedLayout)

        XCTAssertEqual(notifiedScopes, ["shared"])
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

        store.resetLayout()
        store.saveLayout(
            ReaderDisplayLayout(
                pagingMode: .paged,
                spreadMode: .doublePage,
                readingDirection: .leftToRight,
                coverAsSinglePage: true,
                fitMode: .page
            )
        )
        store.resetLayout()
        store.resetLayout()

        XCTAssertEqual(notificationCount, 2)
    }

    func testSettingsSnapshotReaderRefreshOnlyChangesReaderFields() {
        let store = ReaderLayoutPreferencesStore(userDefaults: makeUserDefaults())
        let readerLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        store.saveLayout(readerLayout)

        var snapshot = SettingsSnapshot.empty
        snapshot.recentWindow = .ninetyDays
        snapshot.localLibraryCount = 42
        snapshot.reloadReaderPreferences(preferencesStore: store)

        XCTAssertEqual(snapshot.readerLayout, readerLayout)
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

    private func setStoredLayout(
        _ layout: ReaderDisplayLayout,
        scope: String,
        userDefaults: UserDefaults
    ) {
        let prefix = "reader.layout.\(scope)"
        userDefaults.set(layout.pagingMode.rawValue, forKey: "\(prefix).pagingMode")
        userDefaults.set(layout.spreadMode.rawValue, forKey: "\(prefix).spreadMode")
        userDefaults.set(layout.readingDirection.rawValue, forKey: "\(prefix).readingDirection")
        userDefaults.set(layout.fitMode.rawValue, forKey: "\(prefix).fitMode")
        userDefaults.set(layout.coverAsSinglePage, forKey: "\(prefix).coverAsSinglePage")
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
