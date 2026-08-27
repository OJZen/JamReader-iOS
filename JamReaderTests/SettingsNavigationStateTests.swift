import SwiftUI
import UIKit
import XCTest
@testable import JamReader

final class SettingsNavigationStateTests: XCTestCase {
    func testPersistentSplitSelectionFollowsUIKitIPadSplitArchitecture() {
        XCTAssertTrue(
            AppLayout.usesPersistentSplitSelection(
                isPad: true
            )
        )
        XCTAssertFalse(
            AppLayout.usesPersistentSplitSelection(
                isPad: false
            )
        )
    }

    func testLeafRoutesMapToTheirOwningPane() {
        XCTAssertEqual(
            SettingsNavigationRoute.readerDefaults.settingsPane,
            .reading
        )
        XCTAssertEqual(
            SettingsNavigationRoute.remoteCache.settingsPane,
            .storage
        )
        XCTAssertEqual(
            SettingsNavigationRoute.overview.settingsPane,
            .general
        )
        XCTAssertEqual(
            SettingsNavigationRoute.remoteCache.storageValue,
            SettingsHomePane.storage.rawValue
        )
    }

    func testSettingsCategoriesHaveOneSharedOrder() {
        XCTAssertEqual(
            SettingsHomePane.allCases,
            [.general, .reading, .library, .storage]
        )
    }

    func testPaneRoutesRoundTripThroughStoredValue() {
        for pane in SettingsHomePane.allCases {
            XCTAssertEqual(
                SettingsHomePane.restored(
                    from: pane.navigationRoute.storageValue
                ),
                pane
            )
        }
    }

    func testLegacyRemotePaneRestoresToStorage() {
        XCTAssertEqual(SettingsHomePane.restored(from: "remote"), .storage)
    }

    func testLegacyAboutOverviewAndInvalidPaneRestoreToGeneral() {
        XCTAssertEqual(SettingsHomePane.restored(from: "about"), .general)
        XCTAssertEqual(SettingsHomePane.restored(from: "overview"), .general)
        XCTAssertEqual(SettingsHomePane.restored(from: "unknown"), .general)
        XCTAssertEqual(SettingsHomePane.restored(from: nil), .general)
    }

    func testSelectionStateRepairsLegacyValueAndPersistsSelection() async {
        await MainActor.run {
            let suiteName = "SettingsNavigationStateTests.\(UUID().uuidString)"
            let userDefaults = UserDefaults(suiteName: suiteName)!
            defer {
                userDefaults.removePersistentDomain(forName: suiteName)
            }
            userDefaults.set(
                "overview",
                forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
            )

            let state = SettingsSelectionState(userDefaults: userDefaults)

            XCTAssertEqual(state.selectedPane, .general)
            XCTAssertEqual(
                userDefaults.string(
                    forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
                ),
                SettingsHomePane.general.rawValue
            )

            state.select(.storage)

            XCTAssertEqual(state.selectedPane, .storage)
            XCTAssertEqual(
                userDefaults.string(
                    forKey: AppNavigationStorageKeys.settingsHomeSelectedPane
                ),
                SettingsHomePane.storage.rawValue
            )
        }
    }

    func testPaneControllerCacheReusesEachPaneAcrossSwitches() async {
        await MainActor.run {
            let cache = SettingsPaneControllerCache()
            var creationCount = 0

            let firstGeneral = cache.controller(for: .general) {
                creationCount += 1
                return UIViewController()
            }
            let storage = cache.controller(for: .storage) {
                creationCount += 1
                return UIViewController()
            }
            let secondGeneral = cache.controller(for: .general) {
                creationCount += 1
                return UIViewController()
            }

            XCTAssertTrue(firstGeneral === secondGeneral)
            XCTAssertFalse(firstGeneral === storage)
            XCTAssertEqual(creationCount, 2)
        }
    }

    func testBrowseDetailSelectionsNormalizeForSidebarStorage() {
        let profileID = UUID()

        XCTAssertEqual(
            BrowseStoredNavigationSelection.serverBrowser(profileID).homeStorageValue,
            "server:\(profileID.uuidString)"
        )
        XCTAssertEqual(
            BrowseStoredNavigationSelection.savedFolders(profileID).homeStorageValue,
            "saved-folders"
        )
        XCTAssertEqual(
            BrowseStoredNavigationSelection.offlineShelf(profileID).homeStorageValue,
            "offline-shelf"
        )
    }

    func testBrowseSidebarSelectionRestoresLegacyDetailValues() {
        let profileID = UUID()

        XCTAssertEqual(
            BrowseHomeSplitSelection(storageValue: "browser:\(profileID.uuidString)"),
            .server(profileID)
        )
        XCTAssertEqual(
            BrowseHomeSplitSelection(storageValue: "saved-folders:\(profileID.uuidString)"),
            .savedFolders
        )
        XCTAssertEqual(
            BrowseHomeSplitSelection(storageValue: "offline-shelf:\(profileID.uuidString)"),
            .offlineShelf
        )
    }
}
