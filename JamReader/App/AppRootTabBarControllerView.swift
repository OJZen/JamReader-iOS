import Combine
import SwiftUI
import UIKit

@MainActor
final class AppRootCoordinator: NSObject, UITabBarControllerDelegate {
    let rootViewController: RootTabBarController

    private let dependencies: AppDependencies
    private let libraryListViewModel: LibraryListViewModel
    private let windowScene: UIWindowScene
    private let browseRemoteServerViewModel: RemoteServerListViewModel
    private let presentationCoordinator: UIKitPresentationCoordinator
    private var libraryCoordinator: LibraryTabCoordinator!
    private var browseCoordinator: BrowseTabCoordinator!
    private var settingsCoordinator: SettingsTabCoordinator!
    private var navigationObserver: NSObjectProtocol?
    private var lifecycleObserver: NSObjectProtocol?
    private var importOverlayWindow: UIWindow?
    private var importOverlayVisibilityCancellable: AnyCancellable?

    init(
        dependencies: AppDependencies,
        libraryListViewModel: LibraryListViewModel,
        windowScene: UIWindowScene
    ) {
        self.dependencies = dependencies
        self.libraryListViewModel = libraryListViewModel
        self.windowScene = windowScene
        self.browseRemoteServerViewModel = RemoteServerListViewModel(
            profileStore: dependencies.remoteServerProfileStore,
            folderShortcutStore: dependencies.remoteFolderShortcutStore,
            credentialStore: dependencies.remoteServerCredentialStore,
            browsingService: dependencies.remoteServerBrowsingService,
            readingProgressStore: dependencies.remoteReadingProgressStore,
            remoteOfflineCopyStore: dependencies.remoteOfflineCopyStore,
            remoteOfflineLibrarySnapshotStore: dependencies.remoteOfflineLibrarySnapshotStore,
            remoteBackgroundImportController: dependencies.remoteBackgroundImportController
        )

        let rootViewController = RootTabBarController()
        self.rootViewController = rootViewController
        self.presentationCoordinator = UIKitPresentationCoordinator(
            dependencies: dependencies,
            rootViewController: rootViewController
        )

        super.init()

        let startsCollapsed = adaptiveSplitStartsCollapsed(in: windowScene)
        libraryCoordinator = LibraryTabCoordinator(
            dependencies: dependencies,
            viewModel: libraryListViewModel,
            presenter: presentationCoordinator,
            startsCollapsed: startsCollapsed,
            rootNavigate: { [weak self] route in self?.handle(route) },
            selectTab: { [weak self] tab in self?.select(tab) }
        )
        browseCoordinator = BrowseTabCoordinator(
            dependencies: dependencies,
            viewModel: browseRemoteServerViewModel,
            presenter: presentationCoordinator,
            startsCollapsed: startsCollapsed,
            rootNavigate: { [weak self] route in self?.handle(route) },
            selectTab: { [weak self] tab in self?.select(tab) }
        )
        settingsCoordinator = SettingsTabCoordinator(
            dependencies: dependencies,
            viewModel: libraryListViewModel,
            presenter: presentationCoordinator,
            startsCollapsed: startsCollapsed,
            rootNavigate: { [weak self] route in self?.handle(route) },
            selectTab: { [weak self] tab in self?.select(tab) }
        )

        rootViewController.delegate = self
        rootViewController.configureKeyboardShortcuts { [weak self] tab in
            self?.select(tab)
        }
        rootViewController.view.backgroundColor = .systemGroupedBackground

        if #available(iOS 18.0, *) {
            rootViewController.mode = .tabBar
        }

        installRootTabs()
        rootViewController.selectedIndex = initialSelectedTab.index
        presentationCoordinator.attach(rootViewController: rootViewController)
        installImportOverlay()
        observeNavigationRequests()
        observeLifecycle()
    }

    deinit {
        if let navigationObserver {
            NotificationCenter.default.removeObserver(navigationObserver)
        }
        if let lifecycleObserver {
            NotificationCenter.default.removeObserver(lifecycleObserver)
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        guard let selectedTab = AppRootTab(index: tabBarController.selectedIndex) else {
            return
        }

        UserDefaults.standard.set(
            selectedTab.rawValue,
            forKey: AppNavigationStorageKeys.selectedTab
        )
    }

    func select(_ tab: AppRootTab) {
        repairRootTabsIfNeeded()
        rootViewController.selectedIndex = tab.index
        UserDefaults.standard.set(tab.rawValue, forKey: AppNavigationStorageKeys.selectedTab)
    }

    private var storedSelectedTab: AppRootTab {
        let rawValue = UserDefaults.standard.string(forKey: AppNavigationStorageKeys.selectedTab)
        return rawValue.flatMap(AppRootTab.init(rawValue:)) ?? .library
    }

    private var initialSelectedTab: AppRootTab {
        dependencies.appLaunchPreferencesStore
            .loadDestination()
            .resolvedTab(lastUsedTab: storedSelectedTab)
    }

    private func observeNavigationRequests() {
        navigationObserver = NotificationCenter.default.addObserver(
            forName: .appNavigationRouteRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let route = notification.userInfo?[AppNavigationNotificationKeys.route] as? AppNavigationRoute else {
                return
            }

            Task { @MainActor [weak self] in
                self?.handle(route)
            }
        }
    }

    private func observeLifecycle() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repairRootTabsIfNeeded()
            }
        }
    }

    private func handle(_ route: AppNavigationRoute) {
        switch route {
        case .selectTab(let tab):
            select(tab)
        case .library(let libraryRoute):
            select(.library)
            libraryCoordinator.navigate(libraryRoute)
        case .browse(let browseRoute):
            select(.browse)
            browseCoordinator.navigate(browseRoute)
        case .settings(let settingsRoute):
            select(.settings)
            settingsCoordinator.navigate(settingsRoute)
        }
    }

    private func installImportOverlay() {
        let importController = dependencies.remoteBackgroundImportController
        let overlayRootController = RootOverlayWindowController()
        let overlay = RootTabHostingController(
            rootView: AnyView(
                AppRootOverlayView(
                    controller: importController
                )
                .environment(\.appPresenter, presentationCoordinator)
            )
        )
        overlay.view.backgroundColor = .clear
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        overlay.sizingOptions = [.intrinsicContentSize]
        overlayRootController.embed(
            overlay,
            bottomOffset: AppLayout.bottomBarHeight - Spacing.xxs
        )

        let overlayWindow = PassthroughOverlayWindow(windowScene: windowScene)
        overlayWindow.rootViewController = overlayRootController
        overlayWindow.backgroundColor = .clear
        overlayWindow.windowLevel = .normal + 1
        overlayWindow.isHidden = !hasImportOverlayContent
        importOverlayWindow = overlayWindow

        importOverlayVisibilityCancellable = importController.$activeProgress
            .combineLatest(importController.$feedback)
            .sink { [weak self] activeProgress, feedback in
                self?.importOverlayWindow?.isHidden = activeProgress == nil && feedback == nil
            }
    }

    private var hasImportOverlayContent: Bool {
        let importController = dependencies.remoteBackgroundImportController
        return importController.activeProgress != nil || importController.feedback != nil
    }

    private var rootTabControllers: [UIViewController] {
        [
            libraryCoordinator.rootViewController,
            browseCoordinator.rootViewController,
            settingsCoordinator.rootViewController
        ]
    }

    private func installRootTabs() {
        rootViewController.setViewControllers(rootTabControllers, animated: false)
    }

    private func repairRootTabsIfNeeded() {
        let expectedControllers = rootTabControllers
        let currentControllers = rootViewController.viewControllers ?? []
        let currentItemCount = rootViewController.tabBar.items?.count ?? currentControllers.count
        guard currentItemCount != expectedControllers.count
                || currentControllers.count != expectedControllers.count
                || !zip(currentControllers, expectedControllers).allSatisfy({ $0 === $1 }) else {
            return
        }

        let selectedTab = AppRootTab(index: rootViewController.selectedIndex) ?? storedSelectedTab
        rootViewController.setViewControllers(expectedControllers, animated: false)
        rootViewController.selectedIndex = selectedTab.index
    }
}

@MainActor
private protocol RootTabChildCoordinator: AnyObject {
    var rootViewController: UIViewController { get }
    func pop()
}

@MainActor
private final class LibraryTabCoordinator: RootTabChildCoordinator {
    private let dependencies: AppDependencies
    private let viewModel: LibraryListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let shell: AdaptiveSplitShell
    private var selectedLibraryID: UUID?

    init(
        dependencies: AppDependencies,
        viewModel: LibraryListViewModel,
        presenter: UIKitPresentationCoordinator,
        startsCollapsed: Bool,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.shell = AdaptiveSplitShell(initiallyCollapsed: startsCollapsed)

        configureRoot(tab: .library)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        shell.onExpandWithoutDetail = { [weak self] in
            guard let self, !self.restoreStoredDetailIfNeeded() else {
                return
            }
            self.showPlaceholder()
        }
        installRoot()
        restoreStoredDetailIfNeeded()
    }

    var rootViewController: UIViewController {
        shell.splitViewController
    }

    /// The iPhone stack while the split view is collapsed, otherwise `nil`.
    private var compactNavigationController: UINavigationController? {
        shell.isCollapsed ? shell.compactNavigationController : nil
    }

    private var primaryNavigationController: UINavigationController? {
        shell.primaryNavigationController
    }

    /// The content column while the sidebar is visible, otherwise `nil`.
    private var detailNavigationController: UINavigationController? {
        shell.isCollapsed ? nil : shell.detailNavigationController
    }

    func navigate(_ route: LibraryNavigationRoute) {
        switch route {
        case .home:
            popToRoot()
        case .openLibrary(let libraryID, let folderID):
            openLibrary(libraryID, folderID: folderID)
        case .openFolder(let descriptor, let folderID):
            openFolder(descriptor, folderID: folderID)
        case .openAncestorFolder(let descriptor, let folderID):
            openFolder(descriptor, folderID: folderID, replacingDeeperLevels: true)
        case .continueReading:
            showContinueReading()
        case .specialCollection(let descriptor, let kind):
            pushLibraryDetail(
                LibrarySpecialCollectionView(
                    descriptor: descriptor,
                    kind: kind,
                    dependencies: dependencies
                ),
                title: kind.title
            )
        case .organization(let descriptor, let sectionKind):
            pushLibraryDetail(
                LibraryOrganizationView(
                    descriptor: descriptor,
                    sectionKind: sectionKind,
                    dependencies: dependencies
                ),
                title: sectionKind.title
            )
        case .organizationCollection(let descriptor, let collection):
            pushLibraryDetail(
                LibraryOrganizationCollectionDetailView(
                    descriptor: descriptor,
                    collection: collection,
                    dependencies: dependencies
                ),
                title: collection.displayTitle
            )
        case .sidebarCollection(let libraryID, let collection):
            showSidebarCollection(libraryID, collection: collection)
        }
    }

    func pop() {
        activeNavigationController?.popViewController(animated: true)
    }

    private var activeNavigationController: UINavigationController? {
        compactNavigationController ?? detailNavigationController
    }

    /// The home is built twice: as the iPhone list in the compact stack and as
    /// the sidebar beside the content.
    private func installRoot() {
        for isSidebar in [false, true] {
            let root = makeHostingController(
                LibraryHomeView(
                    viewModel: viewModel,
                    dependencies: dependencies,
                    isSidebar: isSidebar
                )
                .background(Color.surfaceGrouped.ignoresSafeArea()),
                title: AppRootTab.library.title
            )
            root.navigationItem.largeTitleDisplayMode = .always
            let navigationController = isSidebar
                ? shell.primaryNavigationController
                : shell.compactNavigationController
            navigationController.setViewControllers([root], animated: false)
        }
        showPlaceholder()
    }

    private func openLibrary(_ libraryID: UUID, folderID: Int64?, animated: Bool = true) {
        viewModel.reload()
        guard let item = viewModel.items.first(where: { $0.id == libraryID }) else {
            showUnavailable(
                title: String(localized: "Library Unavailable"),
                message: String(localized: "This library is no longer available on this device.")
            )
            return
        }

        selectedLibraryID = item.id
        UserDefaults.standard.set(
            item.id.uuidString,
            forKey: AppNavigationStorageKeys.libraryHomeSelectedLibraryID
        )
        persistSidebarSelection(.library(item.id))
        let resolvedFolderID = folderID ?? LibraryBrowserView.lastOpenedFolderID(for: item.id)
        let controller = makeLibraryBrowser(descriptor: item.descriptor, folderID: resolvedFolderID)

        if let compactNavigationController {
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                animated: animated
            )
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    /// Reopens the stored sidebar selection, falling back to the last library.
    @discardableResult
    private func restoreStoredDetailIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        let storedSelection = defaults.string(forKey: AppNavigationStorageKeys.librarySidebarSelection)
            .flatMap(LibrarySidebarSelection.init(storageValue:))
        switch storedSelection {
        case .continueReading:
            showContinueReading(animated: false)
            return true
        case .collection(let libraryID, let collection)
            where viewModel.items.contains(where: { $0.id == libraryID }):
            showSidebarCollection(libraryID, collection: collection, animated: false)
            return true
        default:
            break
        }

        let storedLibraryID = defaults.string(forKey: AppNavigationStorageKeys.libraryHomeSelectedLibraryID)
        guard let libraryID = storedLibraryID.flatMap(UUID.init(uuidString:)),
              viewModel.items.contains(where: { $0.id == libraryID }) else {
            return false
        }

        openLibrary(libraryID, folderID: nil, animated: false)
        return true
    }

    private func persistSidebarSelection(_ selection: LibrarySidebarSelection) {
        UserDefaults.standard.set(
            selection.storageValue,
            forKey: AppNavigationStorageKeys.librarySidebarSelection
        )
    }

    /// A sidebar collection row replaces the content column. Restored into the
    /// compact stack, the page sits above the library it belongs to.
    private func showSidebarCollection(
        _ libraryID: UUID,
        collection: LibrarySidebarCollection,
        animated: Bool = true
    ) {
        guard let item = viewModel.items.first(where: { $0.id == libraryID }) else {
            return
        }

        selectedLibraryID = item.id
        UserDefaults.standard.set(
            item.id.uuidString,
            forKey: AppNavigationStorageKeys.libraryHomeSelectedLibraryID
        )
        persistSidebarSelection(.collection(item.id, collection))
        let page = makeCollectionPage(descriptor: item.descriptor, collection: collection)
        if let compactNavigationController {
            let libraryRoot = makeLibraryBrowser(descriptor: item.descriptor, folderID: 1)
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, libraryRoot, page].compactMap { $0 },
                animated: animated
            )
        } else {
            detailNavigationController?.setViewControllers([page], animated: false)
        }
    }

    private func makeCollectionPage(
        descriptor: LibraryDescriptor,
        collection: LibrarySidebarCollection
    ) -> UIViewController {
        let controller: UIViewController
        if let kind = collection.specialKind {
            controller = makeHostingController(
                LibrarySpecialCollectionView(descriptor: descriptor, kind: kind, dependencies: dependencies),
                title: kind.title
            )
        } else if let sectionKind = collection.organizationKind {
            controller = makeHostingController(
                LibraryOrganizationView(descriptor: descriptor, sectionKind: sectionKind, dependencies: dependencies),
                title: sectionKind.title
            )
        } else {
            controller = UIViewController()
        }
        controller.navigationItem.largeTitleDisplayMode = .always
        return controller
    }

    private func openFolder(
        _ descriptor: LibraryDescriptor,
        folderID: Int64,
        replacingDeeperLevels: Bool = false
    ) {
        selectedLibraryID = descriptor.id
        UserDefaults.standard.set(
            descriptor.id.uuidString,
            forKey: AppNavigationStorageKeys.libraryHomeSelectedLibraryID
        )
        // Breadcrumb taps return to a level already on the stack instead of pushing it again.
        let identifier = Self.browserIdentifier(libraryID: descriptor.id, folderID: folderID)
        if let navigationController = compactNavigationController ?? detailNavigationController,
           let existing = navigationController.viewControllers.last(where: { $0.restorationIdentifier == identifier }) {
            navigationController.popToViewController(existing, animated: true)
            return
        }

        let controller = makeLibraryBrowser(descriptor: descriptor, folderID: folderID)
        guard let navigationController = compactNavigationController ?? detailNavigationController else {
            return
        }

        // A restored subfolder has no ancestors below it on the stack; going up
        // replaces this library's deeper levels so Back still leads out of the library.
        let browserPrefix = "library.browser.\(descriptor.id.uuidString)."
        if replacingDeeperLevels,
           let firstLevel = navigationController.viewControllers.firstIndex(where: {
               $0.restorationIdentifier?.hasPrefix(browserPrefix) == true
           }) {
            let kept = Array(navigationController.viewControllers[..<firstLevel])
            navigationController.setViewControllers(kept + [controller], animated: true)
            return
        }

        navigationController.pushViewController(controller, animated: true)
    }

    /// The compact stack pushes the page; beside the sidebar it is the content
    /// of its sidebar row.
    private func showContinueReading(animated: Bool = true) {
        let controller = makeHostingController(
            LibraryContinueReadingAllView(dependencies: dependencies),
            title: String(localized: "Continue Reading")
        )
        controller.navigationItem.largeTitleDisplayMode = .always
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: animated)
        } else {
            persistSidebarSelection(.continueReading)
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private static func browserIdentifier(libraryID: UUID, folderID: Int64) -> String {
        "library.browser.\(libraryID.uuidString).\(max(folderID, 1))"
    }

    private func pushLibraryDetail<Content: View>(_ view: Content, title: String) {
        let controller = makeHostingController(view, title: title)
        // Collection pages use a large title with the library and count below it.
        controller.navigationItem.largeTitleDisplayMode = .always
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: true)
        } else if let detailNavigationController {
            detailNavigationController.pushViewController(controller, animated: true)
        }
    }

    private func popToRoot() {
        if let compactNavigationController {
            compactNavigationController.popToRootViewController(animated: true)
        } else {
            showPlaceholder()
        }
    }

    private func makeLibraryBrowser(
        descriptor: LibraryDescriptor,
        folderID: Int64
    ) -> UIViewController {
        let controller = makeHostingController(
            LibraryBrowserView(
                descriptor: descriptor,
                folderID: folderID,
                dependencies: dependencies
            ),
            title: descriptor.displayName
        )
        // Library pages use a large title with the breadcrumb below it.
        controller.navigationItem.largeTitleDisplayMode = .always
        controller.restorationIdentifier = Self.browserIdentifier(libraryID: descriptor.id, folderID: folderID)
        return controller
    }

    private func showPlaceholder() {
        let placeholder = makeHostingController(
            LibraryHomeDetailPlaceholder(
                itemCount: viewModel.items.count,
                onAddComics: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.presenter.presentSheet(
                        LibraryHomeView.addComicsSheetRoute(
                            viewModel: self.viewModel,
                            dependencies: self.dependencies,
                            presenter: self.presenter,
                            navigator: self.navigator
                        )
                    )
                }
            ),
            title: AppRootTab.library.title
        )
        placeholder.restorationIdentifier = AdaptiveSplitShell.placeholderIdentifier
        detailNavigationController?.setViewControllers([placeholder], animated: false)
    }

    private func showUnavailable(title: String, message: String) {
        let controller = makeHostingController(
            ContentUnavailableView(title, systemImage: "books.vertical", description: Text(message)),
            title: title
        )
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: true)
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private func makeHostingController<Content: View>(
        _ view: Content,
        title: String
    ) -> RootTabHostingController {
        let controller = RootTabHostingController(
            rootView: AnyView(
                view
                    .environment(\.appPresenter, presenter)
                    .environment(\.appNavigator, navigator)
                    .environment(\.libraryListViewModel, viewModel)
                    .environment(shell.layoutState)
            )
        )
        controller.title = title
        controller.view.backgroundColor = .systemGroupedBackground
        return controller
    }

    private func configureRoot(tab: AppRootTab) {
        rootViewController.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImage),
            selectedImage: UIImage(systemName: tab.selectedSystemImage)
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
    }
}

@MainActor
private final class BrowseTabCoordinator: RootTabChildCoordinator {
    private let dependencies: AppDependencies
    private let viewModel: RemoteServerListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let shell: AdaptiveSplitShell
    private var editorDraft: RemoteServerEditorDraft?

    init(
        dependencies: AppDependencies,
        viewModel: RemoteServerListViewModel,
        presenter: UIKitPresentationCoordinator,
        startsCollapsed: Bool,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.shell = AdaptiveSplitShell(initiallyCollapsed: startsCollapsed)

        configureRoot(tab: .browse)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        shell.onExpandWithoutDetail = { [weak self] in
            guard let self, !self.restoreStoredDetailIfNeeded() else {
                return
            }
            self.showPlaceholder()
        }
        installRoot()
        restoreStoredDetailIfNeeded()
    }

    var rootViewController: UIViewController {
        shell.splitViewController
    }

    private var compactNavigationController: UINavigationController? {
        shell.isCollapsed ? shell.compactNavigationController : nil
    }

    private var primaryNavigationController: UINavigationController? {
        shell.primaryNavigationController
    }

    private var detailNavigationController: UINavigationController? {
        shell.isCollapsed ? nil : shell.detailNavigationController
    }

    func navigate(_ route: BrowseNavigationRoute) {
        switch route {
        case .home:
            persistDetailSelection("")
            popToRoot()
        case .serverDetail(let profileID):
            showServerDetail(profileID)
        case .serverBrowser(let profileID, let path):
            showServerBrowser(profileID, path: path)
        case .serverBrowserAncestor(let profileID, let path):
            showServerBrowserAncestor(profileID, path: path)
        case .savedFolders(let profileID):
            showSavedFolders(profileID: profileID)
        case .offlineShelf(let profileID):
            showOfflineShelf(profileID: profileID)
        }
    }

    func pop() {
        activeNavigationController?.popViewController(animated: true)
    }

    private var activeNavigationController: UINavigationController? {
        compactNavigationController ?? detailNavigationController
    }

    private var editorDraftBinding: Binding<RemoteServerEditorDraft?> {
        Binding(
            get: { [weak self] in self?.editorDraft },
            set: { [weak self] newValue in
                self?.setEditorDraft(newValue)
            }
        )
    }

    /// The home is built twice: the iPhone list and the sidebar.
    private func installRoot() {
        for isSidebar in [false, true] {
            let root = makeHostingController(
                BrowseHomeView(
                    dependencies: dependencies,
                    viewModel: viewModel,
                    editorDraft: editorDraftBinding,
                    isSidebar: isSidebar
                )
                .background(Color.surfaceGrouped.ignoresSafeArea()),
                title: AppRootTab.browse.title
            )
            root.navigationItem.largeTitleDisplayMode = .always
            let navigationController = isSidebar
                ? shell.primaryNavigationController
                : shell.compactNavigationController
            navigationController.setViewControllers([root], animated: false)
        }
        showPlaceholder()
    }

    private func setEditorDraft(_ draft: RemoteServerEditorDraft?) {
        editorDraft = draft
        guard let draft else {
            presenter.dismissSheet()
            return
        }

        presenter.presentSheet(
            .content(
                id: draft.id,
                content: AnyView(remoteServerEditor(for: draft)),
                onDismiss: { [weak self] in
                    self?.editorDraft = nil
                    self?.viewModel.load()
                }
            )
        )
    }

    private func remoteServerEditor(for draft: RemoteServerEditorDraft) -> some View {
        RemoteServerEditorSheet(
            draft: draft,
            appliesSwiftUIPresentationModifiers: false
        ) { [weak self] updatedDraft in
            guard let self else {
                return AppAlertState(
                    title: String(localized: "Unable to Save"),
                    message: String(localized: "The app navigation coordinator is unavailable.")
                )
            }

            let alertState = viewModel.save(draft: updatedDraft)
            if alertState == nil {
                editorDraft = nil
                presenter.dismissSheet()
            }
            return alertState
        }
        .id(draft.id)
        .environment(\.appPresenter, presenter)
        .environment(\.appNavigator, navigator)
    }

    private func showServerDetail(_ profileID: UUID, animated: Bool = true) {
        viewModel.load()
        guard let profile = profile(for: profileID) else {
            showUnavailable(
                title: String(localized: "Server Unavailable"),
                message: String(localized: "This server is no longer available on this device.")
            )
            return
        }

        let selection = BrowseStoredNavigationSelection.serverDetail(profileID)
        persistHomeSelection(selection.homeStorageValue)
        persistDetailSelection(selection.storageValue)
        let controller = makeHostingController(
            RemoteServerDetailView(
                profile: profile,
                dependencies: dependencies,
                onRequestEdit: { [weak self] draft in
                    self?.setEditorDraft(draft)
                }
            ),
            title: profile.displayTitle
        )
        controller.navigationItem.largeTitleDisplayMode = .never
        setPrimaryDestination(controller, animated: animated)
    }

    private func showServerBrowser(
        _ profileID: UUID,
        path: String?,
        replacesDetailStack: Bool = false,
        animated: Bool = true
    ) {
        viewModel.load()
        guard let profile = profile(for: profileID) else {
            showUnavailable(
                title: String(localized: "Server Unavailable"),
                message: String(localized: "This server is no longer available on this device.")
            )
            return
        }

        persistDetailSelection(BrowseStoredNavigationSelection.serverBrowser(profileID).storageValue)
        let controller = makeServerBrowser(profile, path: path)
        if replacesDetailStack {
            setPrimaryDestination(controller, animated: animated)
        } else {
            pushOrSetDetail(controller, animated: animated)
        }
    }

    private func makeServerBrowser(_ profile: RemoteServerProfile, path: String?) -> UIViewController {
        let controller = makeHostingController(
            RemoteServerBrowserView(
                profile: profile,
                currentPath: path,
                dependencies: dependencies
            ),
            title: profile.displayTitle
        )
        controller.navigationItem.largeTitleDisplayMode = .never
        let resolvedPath = path ?? RemoteServerBrowserViewModel.lastBrowsedPath(for: profile)
        controller.restorationIdentifier = Self.serverBrowserIdentifier(profile.id, path: resolvedPath)
        return controller
    }

    private static func serverBrowserIdentifier(_ profileID: UUID, path: String) -> String {
        "remote.browser.\(profileID.uuidString)|/" + path.split(separator: "/").joined(separator: "/")
    }

    /// Breadcrumb taps return to a level already on the stack; otherwise the
    /// new level replaces this server's folder pages, so Back still leaves the folders.
    private func showServerBrowserAncestor(_ profileID: UUID, path: String) {
        guard let navigationController = activeNavigationController else {
            return
        }

        let identifier = Self.serverBrowserIdentifier(profileID, path: path)
        if let existing = navigationController.viewControllers.last(where: { $0.restorationIdentifier == identifier }) {
            navigationController.popToViewController(existing, animated: true)
            return
        }

        guard let profile = profile(for: profileID) else {
            return
        }

        let controller = makeServerBrowser(profile, path: path)
        let browserPrefix = "remote.browser.\(profileID.uuidString)|"
        if let firstLevel = navigationController.viewControllers.firstIndex(where: {
            $0.restorationIdentifier?.hasPrefix(browserPrefix) == true
        }) {
            let kept = Array(navigationController.viewControllers[..<firstLevel])
            navigationController.setViewControllers(kept + [controller], animated: true)
        } else {
            navigationController.pushViewController(controller, animated: true)
        }
    }

    private func showSavedFolders(profileID: UUID?, animated: Bool = true) {
        let focusedProfile: RemoteServerProfile?
        if let profileID {
            focusedProfile = profile(for: profileID)
        } else {
            focusedProfile = nil
        }
        let selection = BrowseStoredNavigationSelection.savedFolders(profileID)
        persistHomeSelection(selection.homeStorageValue)
        persistDetailSelection(selection.storageValue)
        let controller = makeHostingController(
            SavedRemoteFoldersView(dependencies: dependencies, focusedProfile: focusedProfile),
            title: String(localized: "Saved Folders")
        )
        controller.navigationItem.largeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.never
        setPrimaryDestination(controller, animated: animated)
    }

    private func showOfflineShelf(profileID: UUID?, animated: Bool = true) {
        let focusedProfile: RemoteServerProfile?
        if let profileID {
            focusedProfile = profile(for: profileID)
        } else {
            focusedProfile = nil
        }
        let selection = BrowseStoredNavigationSelection.offlineShelf(profileID)
        persistHomeSelection(selection.homeStorageValue)
        persistDetailSelection(selection.storageValue)
        let controller = makeHostingController(
            RemoteOfflineShelfView(dependencies: dependencies, focusedProfile: focusedProfile),
            title: String(localized: "Offline Shelf")
        )
        controller.navigationItem.largeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.never
        setPrimaryDestination(controller, animated: animated)
    }

    private func setPrimaryDestination(_ controller: UIViewController, animated: Bool = true) {
        if let compactNavigationController {
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                animated: animated
            )
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private func pushOrSetDetail(_ controller: UIViewController, animated: Bool = true) {
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: animated)
        } else if let detailNavigationController {
            if detailNavigationController.viewControllers.isEmpty {
                detailNavigationController.setViewControllers([controller], animated: false)
            } else {
                detailNavigationController.pushViewController(controller, animated: animated)
            }
        }
    }

    @discardableResult
    private func restoreStoredDetailIfNeeded() -> Bool {
        viewModel.load()
        let defaults = UserDefaults.standard
        let storedSelection = defaults.string(forKey: AppNavigationStorageKeys.browseDetailSelection)
            ?? defaults.string(forKey: AppNavigationStorageKeys.browseHomeSelection)
        guard let storedSelection, !storedSelection.isEmpty else {
            return false
        }

        guard let storedRoute = BrowseStoredNavigationSelection(storageValue: storedSelection) else {
            return false
        }

        switch storedRoute {
        case .savedFolders(let profileID):
            showSavedFolders(profileID: profileID, animated: false)
        case .offlineShelf(let profileID):
            showOfflineShelf(profileID: profileID, animated: false)
        case .serverBrowser(let profileID):
            showServerBrowser(
                profileID,
                path: nil,
                replacesDetailStack: true,
                animated: false
            )
        case .serverDetail(let profileID):
            showServerDetail(profileID, animated: false)
        }
        return true
    }

    private func popToRoot() {
        if let compactNavigationController {
            compactNavigationController.popToRootViewController(animated: true)
        } else {
            showPlaceholder()
        }
    }

    private func showPlaceholder() {
        let placeholder = makeHostingController(
            BrowseHomeDetailPlaceholder(
                hasServers: !viewModel.profiles.isEmpty,
                onAddServer: { [weak self] in
                    guard let self else { return }
                    self.setEditorDraft(self.viewModel.makeCreateDraft())
                }
            ),
            title: AppRootTab.browse.title
        )
        placeholder.restorationIdentifier = AdaptiveSplitShell.placeholderIdentifier
        detailNavigationController?.setViewControllers([placeholder], animated: false)
    }

    private func showUnavailable(title: String, message: String) {
        let controller = makeHostingController(
            ContentUnavailableView(title, systemImage: "server.rack", description: Text(message)),
            title: title
        )
        setPrimaryDestination(controller)
    }

    private func profile(for id: UUID) -> RemoteServerProfile? {
        viewModel.profiles.first(where: { $0.id == id })
    }

    private func persistHomeSelection(_ value: String) {
        UserDefaults.standard.set(value, forKey: AppNavigationStorageKeys.browseHomeSelection)
    }

    private func persistDetailSelection(_ value: String) {
        UserDefaults.standard.set(value, forKey: AppNavigationStorageKeys.browseDetailSelection)
    }

    private func makeHostingController<Content: View>(
        _ view: Content,
        title: String
    ) -> RootTabHostingController {
        let controller = RootTabHostingController(
            rootView: AnyView(
                view
                    .environment(\.appPresenter, presenter)
                    .environment(\.appNavigator, navigator)
                    .environment(shell.layoutState)
            )
        )
        controller.title = title
        controller.view.backgroundColor = .systemGroupedBackground
        return controller
    }

    private func configureRoot(tab: AppRootTab) {
        rootViewController.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImage),
            selectedImage: UIImage(systemName: tab.selectedSystemImage)
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
    }

}

@MainActor
final class SettingsPaneControllerCache {
    private var controllers: [SettingsHomePane: UIViewController] = [:]

    func controller(
        for pane: SettingsHomePane,
        makeController: () -> UIViewController
    ) -> UIViewController {
        if let controller = controllers[pane] {
            return controller
        }

        let controller = makeController()
        controllers[pane] = controller
        return controller
    }
}

@MainActor
private final class SettingsTabCoordinator: RootTabChildCoordinator {
    private let dependencies: AppDependencies
    private let viewModel: LibraryListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let selectionState: SettingsSelectionState
    private let paneControllerCache = SettingsPaneControllerCache()
    private let shell: AdaptiveSplitShell

    init(
        dependencies: AppDependencies,
        viewModel: LibraryListViewModel,
        presenter: UIKitPresentationCoordinator,
        startsCollapsed: Bool,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.selectionState = SettingsSelectionState()
        self.shell = AdaptiveSplitShell(initiallyCollapsed: startsCollapsed)

        configureRoot(tab: .settings)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        shell.onExpandWithoutDetail = { [weak self] in
            guard let self else {
                return
            }
            self.showPane(self.selectionState.selectedPane, animated: false)
        }
        installRoot()
    }

    var rootViewController: UIViewController {
        shell.splitViewController
    }

    private var splitViewController: UISplitViewController? {
        shell.isCollapsed ? nil : shell.splitViewController
    }

    private var compactNavigationController: UINavigationController? {
        shell.isCollapsed ? shell.compactNavigationController : nil
    }

    private var primaryNavigationController: UINavigationController? {
        shell.primaryNavigationController
    }

    private var detailNavigationController: UINavigationController? {
        shell.isCollapsed ? nil : shell.detailNavigationController
    }

    func navigate(_ route: SettingsNavigationRoute) {
        switch route {
        case .overview:
            if let compactNavigationController {
                compactNavigationController.popToRootViewController(animated: true)
            } else {
                showPane(.general)
            }
        case .general, .reading, .library, .storage:
            showPane(route.settingsPane)
        case .readerDefaults:
            showLeaf(
                for: route,
                makeHostingController(
                    ReaderDefaultsSettingsView(
                        preferencesStore: dependencies.readerLayoutPreferencesStore
                    ),
                    title: String(localized: "Reading Defaults")
                )
            )
        case .remoteCache:
            showPane(.storage)
        }
    }

    func pop() {
        activeNavigationController?.popViewController(animated: true)
    }

    private var activeNavigationController: UINavigationController? {
        compactNavigationController ?? detailNavigationController
    }

    /// The settings list for the compact stack, the sidebar beside the panes.
    private func installRoot() {
        let home = makeHostingController(
            SettingsHomeView(
                viewModel: viewModel,
                dependencies: dependencies
            ),
            title: AppRootTab.settings.title
        )
        home.navigationItem.largeTitleDisplayMode = .always
        shell.compactNavigationController.setViewControllers([home], animated: false)

        let sidebar = makeHostingController(
            SettingsSidebarView(
                selectionState: selectionState,
                viewModel: viewModel,
                dependencies: dependencies
            ),
            title: AppRootTab.settings.title
        )
        sidebar.navigationItem.largeTitleDisplayMode = .never
        shell.primaryNavigationController.setViewControllers([sidebar], animated: false)
        if !shell.isCollapsed {
            showPane(selectionState.selectedPane, animated: false)
        }
    }

    private func showPane(
        _ pane: SettingsHomePane,
        animated: Bool = true
    ) {
        selectionState.select(pane)
        let controller = paneControllerCache.controller(for: pane) {
            let controller = makeHostingController(
                SettingsPaneContentView(
                    pane: pane,
                    viewModel: viewModel,
                    dependencies: dependencies
                ),
                title: pane.titleString
            )
            controller.navigationItem.largeTitleDisplayMode = .never
            return controller
        }

        if let compactNavigationController {
            if compactNavigationController.topViewController === controller {
                return
            }

            if compactNavigationController.viewControllers.contains(where: { $0 === controller }) {
                compactNavigationController.popToViewController(controller, animated: animated)
            } else {
                compactNavigationController.setViewControllers(
                    [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                    animated: animated
                )
            }
        } else if let detailNavigationController {
            if detailNavigationController.topViewController !== controller {
                if detailNavigationController.viewControllers.contains(where: { $0 === controller }) {
                    detailNavigationController.popToViewController(controller, animated: animated)
                } else {
                    detailNavigationController.setViewControllers([controller], animated: false)
                }
            }
            splitViewController?.show(.secondary)
        }
    }

    private func showLeaf(
        for route: SettingsNavigationRoute,
        _ controller: UIViewController
    ) {
        showPane(route.settingsPane, animated: false)
        controller.navigationItem.largeTitleDisplayMode = .never
        activeNavigationController?.pushViewController(controller, animated: true)
        splitViewController?.show(.secondary)
    }

    private func makeHostingController<Content: View>(
        _ view: Content,
        title: String
    ) -> RootTabHostingController {
        let controller = RootTabHostingController(
            rootView: AnyView(
                view
                    .environment(\.appPresenter, presenter)
                    .environment(\.appNavigator, navigator)
                    .environment(shell.layoutState)
            )
        )
        controller.title = title
        controller.view.backgroundColor = .systemGroupedBackground
        return controller
    }

    private func configureRoot(tab: AppRootTab) {
        rootViewController.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImage),
            selectedImage: UIImage(systemName: tab.selectedSystemImage)
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
    }
}

extension AppRootTab {
    var title: String {
        switch self {
        case .library:
            return String(localized: "Library")
        case .browse:
            return String(localized: "Remote")
        case .settings:
            return String(localized: "Settings")
        }
    }

    var index: Int {
        switch self {
        case .library:
            return 0
        case .browse:
            return 1
        case .settings:
            return 2
        }
    }

    init?(index: Int) {
        switch index {
        case 0:
            self = .library
        case 1:
            self = .browse
        case 2:
            self = .settings
        default:
            return nil
        }
    }
}

final class RootTabBarController: UITabBarController {
    private var selectTabHandler: ((AppRootTab) -> Void)?

    func configureKeyboardShortcuts(_ handler: @escaping (AppRootTab) -> Void) {
        selectTabHandler = handler
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeKeyCommand(
                input: "1",
                title: AppRootTab.library.title,
                action: #selector(selectLibraryTab)
            ),
            makeKeyCommand(
                input: "2",
                title: AppRootTab.browse.title,
                action: #selector(selectBrowseTab)
            ),
            makeKeyCommand(
                input: "3",
                title: AppRootTab.settings.title,
                action: #selector(selectSettingsTab)
            )
        ]
    }

    private func makeKeyCommand(
        input: String,
        title: String,
        action: Selector
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: .command,
            action: action
        )
        command.discoverabilityTitle = title
        return command
    }

    @objc private func selectLibraryTab() {
        selectTabHandler?(.library)
    }

    @objc private func selectBrowseTab() {
        selectTabHandler?(.browse)
    }

    @objc private func selectSettingsTab() {
        selectTabHandler?(.settings)
    }
}

final class RootTabHostingController: UIHostingController<AnyView> {}

final class RootOverlayWindowController: UIViewController {
    override func loadView() {
        let view = PassthroughOverlayView()
        view.backgroundColor = .clear
        self.view = view
    }

    func embed(
        _ controller: UIViewController,
        bottomOffset: CGFloat = 0
    ) {
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.setContentHuggingPriority(.required, for: .vertical)

        let fillWidth = controller.view.widthAnchor.constraint(equalTo: view.widthAnchor)
        fillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            controller.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controller.view.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -bottomOffset
            ),
            controller.view.widthAnchor.constraint(lessThanOrEqualToConstant: AppLayout.overlayMaxWidth),
            fillWidth
        ])
        controller.didMove(toParent: self)
    }
}

final class PassthroughOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView === self || hitView === rootViewController?.view {
            return nil
        }
        return hitView
    }
}

final class PassthroughOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
