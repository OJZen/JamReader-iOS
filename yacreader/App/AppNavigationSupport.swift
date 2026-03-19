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
}

enum AppNavigationRouter {
    @MainActor
    static func openLibrary(_ libraryID: UUID) {
        let defaults = UserDefaults.standard
        defaults.set(AppRootTab.library.rawValue, forKey: AppNavigationStorageKeys.selectedTab)
        defaults.set(libraryID.uuidString, forKey: AppNavigationStorageKeys.pendingFocusedLibraryID)
    }
}
