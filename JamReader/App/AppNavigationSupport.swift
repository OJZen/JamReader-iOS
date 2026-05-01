import Foundation
import SwiftUI
import UIKit

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
    static let browseHomeSelection = "browseHome.selection"
    static let browseHomeColumnVisibility = "browseHome.columnVisibility"
    static let settingsHomeSelectedPane = "settingsHome.selectedPane"
}

enum AppNavigationRoute {
    case selectTab(AppRootTab)
    case library(LibraryNavigationRoute)
    case browse(BrowseNavigationRoute)
    case settings(SettingsNavigationRoute)
}

enum LibraryNavigationRoute {
    case home
    case openLibrary(UUID, folderID: Int64?)
    case openFolder(LibraryDescriptor, folderID: Int64)
    case specialCollection(LibraryDescriptor, LibrarySpecialCollectionKind)
    case organization(LibraryDescriptor, LibraryOrganizationSectionKind)
    case organizationCollection(LibraryDescriptor, LibraryOrganizationCollection)
}

enum BrowseNavigationRoute {
    case home
    case serverDetail(UUID)
    case serverBrowser(UUID, path: String?)
    case savedFolders(UUID?)
    case offlineShelf(UUID?)
}

enum SettingsNavigationRoute {
    case overview
    case reading
    case remote
    case storage
    case about
    case remoteNetwork
    case remoteCache
}

struct LocalReaderPresentation {
    let descriptor: LibraryDescriptor
    let comic: LibraryComic
    let navigationContext: ReaderNavigationContext?
    let sourceFrame: CGRect
    let previewImage: UIImage?
    let transitionStyle: ReaderHeroTransitionStyle
    let onComicUpdated: ((LibraryComic) -> Void)?
    let onDismiss: (() -> Void)?

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext?,
        sourceFrame: CGRect,
        previewImage: UIImage?,
        transitionStyle: ReaderHeroTransitionStyle = .coverZoom,
        onComicUpdated: ((LibraryComic) -> Void)?,
        onDismiss: (() -> Void)?
    ) {
        self.descriptor = descriptor
        self.comic = comic
        self.navigationContext = navigationContext
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
        self.transitionStyle = transitionStyle
        self.onComicUpdated = onComicUpdated
        self.onDismiss = onDismiss
    }
}

struct RemoteReaderPresentation {
    let profile: RemoteServerProfile
    let item: RemoteDirectoryItem
    let openMode: RemoteComicOpenMode
    let referenceOverride: RemoteComicFileReference?
    let sourceFrame: CGRect
    let previewImage: UIImage?
    let transitionStyle: ReaderHeroTransitionStyle
    let onDismiss: (() -> Void)?

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        openMode: RemoteComicOpenMode,
        referenceOverride: RemoteComicFileReference?,
        sourceFrame: CGRect,
        previewImage: UIImage?,
        transitionStyle: ReaderHeroTransitionStyle = .coverZoom,
        onDismiss: (() -> Void)?
    ) {
        self.profile = profile
        self.item = item
        self.openMode = openMode
        self.referenceOverride = referenceOverride
        self.sourceFrame = sourceFrame
        self.previewImage = previewImage
        self.transitionStyle = transitionStyle
        self.onDismiss = onDismiss
    }
}

enum ReaderPresentationRoute {
    case local(LocalReaderPresentation)
    case remote(RemoteReaderPresentation)
}

enum ReaderHeroTransitionStyle {
    /// File-manager style: the thumbnail cover expands into the full-screen reader.
    case coverZoom
    /// Library style: the cover/card lifts forward while the reader fades in behind it.
    case libraryLift
}

enum AppSheetRoute: Identifiable {
    case content(id: AnyHashable, content: AnyView, onDismiss: (() -> Void)? = nil)

    var id: AnyHashable {
        switch self {
        case .content(let id, _, _):
            return id
        }
    }

    var content: AnyView {
        switch self {
        case .content(_, let content, _):
            return content
        }
    }

    var onDismiss: (() -> Void)? {
        switch self {
        case .content(_, _, let onDismiss):
            return onDismiss
        }
    }
}

@MainActor
final class AppNavigator {
    private var navigationHandler: (AppNavigationRoute) -> Void
    private var tabSelectionHandler: (AppRootTab) -> Void
    private var popHandler: () -> Void

    init(
        navigate: @escaping (AppNavigationRoute) -> Void = { _ in },
        selectTab: @escaping (AppRootTab) -> Void = { _ in },
        pop: @escaping () -> Void = {}
    ) {
        self.navigationHandler = navigate
        self.tabSelectionHandler = selectTab
        self.popHandler = pop
    }

    func update(
        navigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void,
        pop: @escaping () -> Void
    ) {
        self.navigationHandler = navigate
        self.tabSelectionHandler = selectTab
        self.popHandler = pop
    }

    func navigate(_ route: AppNavigationRoute) {
        navigationHandler(route)
    }

    func selectTab(_ tab: AppRootTab) {
        tabSelectionHandler(tab)
    }

    func pop() {
        popHandler()
    }
}

extension Notification.Name {
    static let appNavigationRouteRequested = Notification.Name("JamReader.appNavigationRouteRequested")
}

enum AppNavigationNotificationKeys {
    static let route = "route"
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

        NotificationCenter.default.post(
            name: .appNavigationRouteRequested,
            object: nil,
            userInfo: [
                AppNavigationNotificationKeys.route: AppNavigationRoute.library(
                    .openLibrary(libraryID, folderID: folderID)
                )
            ]
        )
    }
}

private struct AppPresenterEnvironmentKey: EnvironmentKey {
    static let defaultValue: UIKitPresentationCoordinator? = nil
}

private struct AppNavigatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppNavigator? = nil
}

extension EnvironmentValues {
    var appPresenter: UIKitPresentationCoordinator? {
        get { self[AppPresenterEnvironmentKey.self] }
        set { self[AppPresenterEnvironmentKey.self] = newValue }
    }

    var appNavigator: AppNavigator? {
        get { self[AppNavigatorEnvironmentKey.self] }
        set { self[AppNavigatorEnvironmentKey.self] = newValue }
    }
}
