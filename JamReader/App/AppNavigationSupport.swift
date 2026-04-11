import Foundation
import SwiftUI

enum AppRootTab: String, Hashable {
    case library
    case browse
    case settings

    var systemImage: String {
        switch self {
        case .library:
            return "books.vertical.fill"
        case .browse:
            return "globe.asia.australia.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

enum AppNavigationStorageKeys {
    static let selectedTab = "appRoot.selectedTab"
    static let pendingFocusedLibraryID = "libraryHome.pendingFocusedLibraryID"
    static let pendingFocusedFolderID = "libraryHome.pendingFocusedFolderID"
}

enum AppNavigationRouter {
    @MainActor
    static func openLibrary(_ libraryID: UUID, folderID: Int64? = nil) {
        let defaults = UserDefaults.standard
        defaults.set(AppRootTab.library.rawValue, forKey: AppNavigationStorageKeys.selectedTab)
        defaults.set(libraryID.uuidString, forKey: AppNavigationStorageKeys.pendingFocusedLibraryID)
        if let folderID {
            defaults.set(String(max(1, folderID)), forKey: AppNavigationStorageKeys.pendingFocusedFolderID)
        } else {
            defaults.removeObject(forKey: AppNavigationStorageKeys.pendingFocusedFolderID)
        }
    }
}
