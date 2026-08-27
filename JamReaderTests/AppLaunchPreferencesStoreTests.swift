import XCTest
@testable import JamReader

final class AppLaunchPreferencesStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testLaunchDestinationDefaultsToLastUsedTabWhenUnset() {
        let store = AppLaunchPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadDestination(), .lastUsedTab)
    }

    func testLaunchDestinationRoundTripsEverySupportedValue() {
        for destination in AppLaunchDestination.allCases {
            let userDefaults = makeUserDefaults()
            let store = AppLaunchPreferencesStore(userDefaults: userDefaults)

            store.saveDestination(destination)

            XCTAssertEqual(
                AppLaunchPreferencesStore(userDefaults: userDefaults)
                    .loadDestination(),
                destination
            )
        }
    }

    func testInvalidLaunchDestinationRepairsStoredValue() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(
            "unknown",
            forKey: AppLaunchPreferencesStore.destinationStorageKey
        )

        let destination = AppLaunchPreferencesStore(userDefaults: userDefaults)
            .loadDestination()

        XCTAssertEqual(destination, .lastUsedTab)
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppLaunchPreferencesStore.destinationStorageKey
            ),
            AppLaunchDestination.lastUsedTab.rawValue
        )
    }

    func testInvalidLaunchDestinationTypeRepairsStoredValue() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(
            42,
            forKey: AppLaunchPreferencesStore.destinationStorageKey
        )

        let destination = AppLaunchPreferencesStore(userDefaults: userDefaults)
            .loadDestination()

        XCTAssertEqual(destination, .lastUsedTab)
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppLaunchPreferencesStore.destinationStorageKey
            ),
            AppLaunchDestination.lastUsedTab.rawValue
        )
    }

    func testSavingLaunchDestinationOnlyNotifiesForEffectiveChanges() {
        let notificationCenter = NotificationCenter()
        let store = AppLaunchPreferencesStore(
            userDefaults: makeUserDefaults(),
            notificationCenter: notificationCenter
        )
        var notificationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .appLaunchPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        store.saveDestination(.lastUsedTab)
        store.saveDestination(.library)
        store.saveDestination(.library)
        store.saveDestination(.browse)

        XCTAssertEqual(notificationCount, 2)
    }

    func testLaunchDestinationResolvesOnlyTheInitialRootTab() {
        XCTAssertEqual(
            AppLaunchDestination.lastUsedTab.resolvedTab(lastUsedTab: .settings),
            .settings
        )
        XCTAssertEqual(
            AppLaunchDestination.library.resolvedTab(lastUsedTab: .settings),
            .library
        )
        XCTAssertEqual(
            AppLaunchDestination.browse.resolvedTab(lastUsedTab: .settings),
            .browse
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "AppLaunchPreferencesStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
