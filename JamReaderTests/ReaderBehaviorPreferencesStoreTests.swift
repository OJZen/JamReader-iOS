import XCTest
@testable import JamReader

final class ReaderBehaviorPreferencesStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testKeepsScreenAwakeDefaultsToEnabled() {
        let store = ReaderBehaviorPreferencesStore(userDefaults: makeUserDefaults())

        XCTAssertTrue(store.loadKeepsScreenAwake())
    }

    func testKeepsScreenAwakeRoundTrips() {
        let userDefaults = makeUserDefaults()
        let store = ReaderBehaviorPreferencesStore(userDefaults: userDefaults)

        store.saveKeepsScreenAwake(false)

        XCTAssertFalse(
            ReaderBehaviorPreferencesStore(userDefaults: userDefaults).loadKeepsScreenAwake()
        )

        store.saveKeepsScreenAwake(true)

        XCTAssertTrue(
            ReaderBehaviorPreferencesStore(userDefaults: userDefaults).loadKeepsScreenAwake()
        )
    }

    func testInvalidKeepsScreenAwakeTypeRepairsToEnabledThenCanBeDisabled() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(
            "invalid",
            forKey: ReaderBehaviorPreferencesStore.keepsScreenAwakeStorageKey
        )
        let store = ReaderBehaviorPreferencesStore(userDefaults: userDefaults)

        XCTAssertTrue(store.loadKeepsScreenAwake())
        XCTAssertEqual(
            userDefaults.object(
                forKey: ReaderBehaviorPreferencesStore.keepsScreenAwakeStorageKey
            ) as? NSNumber,
            NSNumber(value: true)
        )

        store.saveKeepsScreenAwake(false)

        XCTAssertFalse(store.loadKeepsScreenAwake())
        XCTAssertEqual(
            userDefaults.object(
                forKey: ReaderBehaviorPreferencesStore.keepsScreenAwakeStorageKey
            ) as? NSNumber,
            NSNumber(value: false)
        )
    }

    func testBehaviorNotificationOnlyPostsForPersistedChanges() {
        let store = ReaderBehaviorPreferencesStore(userDefaults: makeUserDefaults())
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .readerBehaviorPreferencesDidChange,
            object: store,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.saveKeepsScreenAwake(true)
        store.saveKeepsScreenAwake(false)
        store.saveKeepsScreenAwake(false)
        store.saveKeepsScreenAwake(true)
        store.saveKeepsScreenAwake(true)

        XCTAssertEqual(notificationCount, 2)
    }

    func testIdleTimerPolicyRequiresEveryCondition() {
        let cases: [(isSceneActive: Bool, hasDocument: Bool, keepsScreenAwake: Bool, expected: Bool)] = [
            (false, false, false, false),
            (false, false, true, false),
            (false, true, false, false),
            (false, true, true, false),
            (true, false, false, false),
            (true, false, true, false),
            (true, true, false, false),
            (true, true, true, true)
        ]

        for testCase in cases {
            XCTAssertEqual(
                ReaderIdleTimerPolicy.shouldDisableIdleTimer(
                    isSceneActive: testCase.isSceneActive,
                    hasDocument: testCase.hasDocument,
                    keepsScreenAwake: testCase.keepsScreenAwake
                ),
                testCase.expected,
                "isSceneActive=\(testCase.isSceneActive), hasDocument=\(testCase.hasDocument), keepsScreenAwake=\(testCase.keepsScreenAwake)"
            )
        }
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ReaderBehaviorPreferencesStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
