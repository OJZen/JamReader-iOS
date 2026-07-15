import SwiftUI
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
            SettingsNavigationRoute.readerDefaults(.manga).settingsPane,
            .reading
        )
        XCTAssertEqual(
            SettingsNavigationRoute.remoteCache.settingsPane,
            .storage
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

    func testInvalidPaneRestoresToOverview() {
        XCTAssertEqual(SettingsHomePane.restored(from: "unknown"), .overview)
        XCTAssertEqual(SettingsHomePane.restored(from: nil), .overview)
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
