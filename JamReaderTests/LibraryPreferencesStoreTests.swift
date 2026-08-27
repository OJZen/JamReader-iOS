import XCTest
@testable import JamReader

final class LibraryPreferencesStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testRecentWindowUsesDefaultWhenUnset() {
        let store = LibraryPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadRecentWindow(), .defaultOption)
    }

    func testRecentWindowRoundTrips() {
        let userDefaults = makeUserDefaults()
        let store = LibraryPreferencesStore(userDefaults: userDefaults)

        store.saveRecentWindow(.thirtyDays)

        XCTAssertEqual(
            LibraryPreferencesStore(userDefaults: userDefaults).loadRecentWindow(),
            .thirtyDays
        )
    }

    func testInvalidRecentWindowFallsBackAndRepairsStoredValue() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(365, forKey: LibraryPreferencesStore.recentWindowStorageKey)

        let option = LibraryPreferencesStore(userDefaults: userDefaults)
            .loadRecentWindow()

        XCTAssertEqual(option, .defaultOption)
        XCTAssertEqual(
            userDefaults.integer(
                forKey: LibraryPreferencesStore.recentWindowStorageKey
            ),
            LibraryRecentWindowOption.defaultOption.rawValue
        )
    }

    func testSettingsSnapshotLibraryRefreshOnlyChangesLibraryFields() {
        let store = LibraryPreferencesStore(userDefaults: makeUserDefaults())
        store.saveRecentWindow(.thirtyDays)

        var snapshot = SettingsSnapshot.empty
        let readerLayout = ReaderDisplayLayout(
            pagingMode: .paged,
            spreadMode: .doublePage,
            readingDirection: .rightToLeft,
            coverAsSinglePage: false,
            fitMode: .height
        )
        snapshot.readerLayout = readerLayout
        snapshot.localLibraryCount = 42
        snapshot.reloadLibraryPreferences(preferencesStore: store)

        XCTAssertEqual(snapshot.recentWindow, .thirtyDays)
        XCTAssertEqual(snapshot.readerLayout, readerLayout)
        XCTAssertEqual(snapshot.localLibraryCount, 42)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "LibraryPreferencesStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
