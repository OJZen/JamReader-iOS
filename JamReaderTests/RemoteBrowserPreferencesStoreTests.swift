import XCTest
@testable import JamReader

final class RemoteBrowserPreferencesStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testDefaultFolderImportScopeIncludesSubfoldersWhenUnset() {
        let store = RemoteBrowserPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadDefaultFolderImportScope(), .includeSubfolders)
    }

    func testDefaultFolderImportScopeRoundTripsSupportedValues() {
        for scope in [
            RemoteDirectoryImportScope.currentFolderOnly,
            .includeSubfolders
        ] {
            let userDefaults = makeUserDefaults()
            let store = RemoteBrowserPreferencesStore(userDefaults: userDefaults)

            store.saveDefaultFolderImportScope(scope)

            XCTAssertEqual(
                RemoteBrowserPreferencesStore(userDefaults: userDefaults)
                    .loadDefaultFolderImportScope(),
                scope
            )
        }
    }

    func testUnsupportedDefaultFolderImportScopeRepairsToIncludeSubfolders() {
        for rawValue in [RemoteDirectoryImportScope.visibleResults.rawValue, "unknown"] {
            let userDefaults = makeUserDefaults()
            userDefaults.set(
                rawValue,
                forKey: RemoteBrowserPreferencesStore.defaultFolderImportScopeStorageKey
            )

            let scope = RemoteBrowserPreferencesStore(userDefaults: userDefaults)
                .loadDefaultFolderImportScope()

            XCTAssertEqual(scope, .includeSubfolders)
            XCTAssertEqual(
                userDefaults.string(
                    forKey: RemoteBrowserPreferencesStore.defaultFolderImportScopeStorageKey
                ),
                RemoteDirectoryImportScope.includeSubfolders.rawValue
            )
        }
    }

    func testUnsupportedScopeIsNotSavedOrAnnounced() {
        let store = RemoteBrowserPreferencesStore(userDefaults: makeUserDefaults())
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .remoteBrowserPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveDefaultFolderImportScope(.visibleResults)
        store.saveDefaultFolderImportScope(.currentFolderOnly)
        store.saveDefaultFolderImportScope(.currentFolderOnly)

        XCTAssertEqual(store.loadDefaultFolderImportScope(), .currentFolderOnly)
        XCTAssertEqual(notificationCount, 1)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "RemoteBrowserPreferencesStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
