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

        store.saveLayout(mangaLayout, for: .manga)
        store.saveLayout(comicLayout, for: .comic)

        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .manga), mangaLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .yonkoma), mangaLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .comic), comicLayout)
        XCTAssertEqual(ReaderLayoutPreferencesStore(userDefaults: userDefaults).loadLayout(for: .webComic), comicLayout)
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
