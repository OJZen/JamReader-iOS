import XCTest
@testable import JamReader

final class RemoteCachePolicyStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testDefaultPresetIsOneGigabyte() {
        let store = RemoteCachePolicyStore(userDefaults: makeUserDefaults())

        XCTAssertEqual(store.loadPreset(), .oneGigabyte)
        XCTAssertEqual(store.loadPolicy().maximumCachedComicFileCount, 24)
        XCTAssertEqual(store.loadPolicy().maximumTotalCacheBytes, 1 * 1_024 * 1_024 * 1_024)
    }

    func testSavedPresetRoundTrips() {
        let userDefaults = makeUserDefaults()
        let store = RemoteCachePolicyStore(userDefaults: userDefaults)

        store.savePreset(.fourGigabytes)

        XCTAssertEqual(RemoteCachePolicyStore(userDefaults: userDefaults).loadPreset(), .fourGigabytes)
        XCTAssertEqual(store.loadPolicy().maximumCachedComicFileCount, 96)
        XCTAssertEqual(store.loadPolicy().maximumTotalCacheBytes, 4 * 1_024 * 1_024 * 1_024)
    }

    func testFullCopyWhileReadingDefaultsToEnabled() {
        let store = RemoteCachePolicyStore(userDefaults: makeUserDefaults())

        XCTAssertTrue(store.loadDownloadsFullCopyWhileReading())
    }

    func testFullCopyWhileReadingRoundTrips() {
        let userDefaults = makeUserDefaults()
        let store = RemoteCachePolicyStore(userDefaults: userDefaults)

        store.saveDownloadsFullCopyWhileReading(false)

        XCTAssertFalse(
            RemoteCachePolicyStore(userDefaults: userDefaults)
                .loadDownloadsFullCopyWhileReading()
        )

        store.saveDownloadsFullCopyWhileReading(true)

        XCTAssertTrue(
            RemoteCachePolicyStore(userDefaults: userDefaults)
                .loadDownloadsFullCopyWhileReading()
        )
    }

    func testInvalidFullCopyPreferenceRepairsToEnabled() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(
            "invalid",
            forKey: RemoteCachePolicyStore.downloadFullCopyWhileReadingStorageKey
        )

        let store = RemoteCachePolicyStore(userDefaults: userDefaults)

        XCTAssertTrue(store.loadDownloadsFullCopyWhileReading())
        XCTAssertTrue(
            userDefaults.bool(
                forKey: RemoteCachePolicyStore.downloadFullCopyWhileReadingStorageKey
            )
        )
    }

    func testLegacyPresetValuesAreMappedToCurrentPresets() {
        XCTAssertEqual(loadPreset(fromLegacyRawValue: "compact"), .fiveHundredMB)
        XCTAssertEqual(loadPreset(fromLegacyRawValue: "balanced"), .twoGigabytes)
        XCTAssertEqual(loadPreset(fromLegacyRawValue: "extended"), .fourGigabytes)
    }

    func testUnknownStoredValueFallsBackToDefaultPreset() {
        XCTAssertEqual(loadPreset(fromLegacyRawValue: "unknown"), .oneGigabyte)
    }

    func testPresetPoliciesExposeExpectedLimits() {
        XCTAssertEqual(RemoteComicCachePolicyPreset.fiveHundredMB.title, "500 MB")
        XCTAssertEqual(RemoteComicCachePolicyPreset.fiveHundredMB.policy.maximumCachedComicFileCount, 12)
        XCTAssertEqual(RemoteComicCachePolicyPreset.fiveHundredMB.policy.maximumTotalCacheBytes, 500 * 1_024 * 1_024)

        XCTAssertEqual(RemoteComicCachePolicyPreset.twoGigabytes.title, "2048 MB")
        XCTAssertEqual(RemoteComicCachePolicyPreset.twoGigabytes.policy.maximumCachedComicFileCount, 48)
        XCTAssertEqual(RemoteComicCachePolicyPreset.twoGigabytes.policy.maximumTotalCacheBytes, 2 * 1_024 * 1_024 * 1_024)

        XCTAssertEqual(RemoteComicCachePolicyPreset.unlimited.title, "Unlimited")
        XCTAssertEqual(RemoteComicCachePolicyPreset.unlimited.policy.maximumCachedComicFileCount, .max)
        XCTAssertEqual(RemoteComicCachePolicyPreset.unlimited.policy.maximumTotalCacheBytes, .max)
    }

    private func loadPreset(fromLegacyRawValue rawValue: String) -> RemoteComicCachePolicyPreset {
        let userDefaults = makeUserDefaults()
        userDefaults.set(rawValue, forKey: "remoteBrowser.cachePolicyPreset")
        return RemoteCachePolicyStore(userDefaults: userDefaults).loadPreset()
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "RemoteCachePolicyStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
