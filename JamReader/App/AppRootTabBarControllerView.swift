import SwiftUI
import UIKit

@MainActor
final class AppRootCoordinator: NSObject, UITabBarControllerDelegate {
    let rootViewController: RootTabBarController

    private let dependencies: AppDependencies
    private let libraryListViewModel: LibraryListViewModel
    private let browseRemoteServerViewModel: RemoteServerListViewModel
    private let presentationCoordinator: UIKitPresentationCoordinator
    private var libraryCoordinator: LibraryTabCoordinator!
    private var browseCoordinator: BrowseTabCoordinator!
    private var settingsCoordinator: SettingsTabCoordinator!
    private var navigationObserver: NSObjectProtocol?

    init(
        dependencies: AppDependencies,
        libraryListViewModel: LibraryListViewModel
    ) {
        self.dependencies = dependencies
        self.libraryListViewModel = libraryListViewModel
        self.browseRemoteServerViewModel = RemoteServerListViewModel(
            profileStore: dependencies.remoteServerProfileStore,
            folderShortcutStore: dependencies.remoteFolderShortcutStore,
            credentialStore: dependencies.remoteServerCredentialStore,
            browsingService: dependencies.remoteServerBrowsingService,
            readingProgressStore: dependencies.remoteReadingProgressStore
        )

        let rootViewController = RootTabBarController()
        self.rootViewController = rootViewController
        self.presentationCoordinator = UIKitPresentationCoordinator(
            dependencies: dependencies,
            rootViewController: rootViewController
        )

        super.init()

        libraryCoordinator = LibraryTabCoordinator(
            dependencies: dependencies,
            viewModel: libraryListViewModel,
            presenter: presentationCoordinator,
            rootNavigate: { [weak self] route in self?.handle(route) },
            selectTab: { [weak self] tab in self?.select(tab) }
        )
        browseCoordinator = BrowseTabCoordinator(
            dependencies: dependencies,
            viewModel: browseRemoteServerViewModel,
            presenter: presentationCoordinator,
            rootNavigate: { [weak self] route in self?.handle(route) },
            selectTab: { [weak self] tab in self?.select(tab) }
        )
        settingsCoordinator = SettingsTabCoordinator(
            dependencies: dependencies,
            viewModel: libraryListViewModel,
            presenter: presentationCoordinator,
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

        rootViewController.setViewControllers(
            [
                libraryCoordinator.rootViewController,
                browseCoordinator.rootViewController,
                settingsCoordinator.rootViewController
            ],
            animated: false
        )
        rootViewController.selectedIndex = storedSelectedTab.index
        presentationCoordinator.attach(rootViewController: rootViewController)
        installImportOverlay()
        observeNavigationRequests()
    }

    deinit {
        if let navigationObserver {
            NotificationCenter.default.removeObserver(navigationObserver)
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
        rootViewController.selectedIndex = tab.index
        UserDefaults.standard.set(tab.rawValue, forKey: AppNavigationStorageKeys.selectedTab)
    }

    private var storedSelectedTab: AppRootTab {
        let rawValue = UserDefaults.standard.string(forKey: AppNavigationStorageKeys.selectedTab)
        return rawValue.flatMap(AppRootTab.init(rawValue:)) ?? .library
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
        let overlayContainer = PassthroughOverlayView()
        overlayContainer.backgroundColor = .clear
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false

        let overlay = RootTabHostingController(
            rootView: AnyView(
                AppRootOverlayView(
                    controller: dependencies.remoteBackgroundImportController,
                    bottomBarHeight: AppLayout.bottomBarHeight
                )
                .environment(\.appPresenter, presentationCoordinator)
            )
        )
        overlay.view.backgroundColor = .clear
        overlay.view.translatesAutoresizingMaskIntoConstraints = false

        rootViewController.view.addSubview(overlayContainer)
        NSLayoutConstraint.activate([
            overlayContainer.leadingAnchor.constraint(equalTo: rootViewController.view.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: rootViewController.view.trailingAnchor),
            overlayContainer.topAnchor.constraint(equalTo: rootViewController.view.topAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: rootViewController.view.bottomAnchor)
        ])

        rootViewController.addChild(overlay)
        overlayContainer.addSubview(overlay.view)
        NSLayoutConstraint.activate([
            overlay.view.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            overlay.view.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
            overlay.view.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            overlay.view.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor)
        ])
        overlay.didMove(toParent: rootViewController)
    }
}

@MainActor
private protocol RootTabChildCoordinator: AnyObject {
    var rootViewController: UIViewController { get }
    func pop()
}

@MainActor
private final class LibraryTabCoordinator: RootTabChildCoordinator {
    let rootViewController: UIViewController

    private let dependencies: AppDependencies
    private let viewModel: LibraryListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let usesSplitLayout: Bool
    private let compactNavigationController: UINavigationController?
    private let primaryNavigationController: UINavigationController?
    private let detailNavigationController: UINavigationController?
    private var selectedLibraryID: UUID?

    init(
        dependencies: AppDependencies,
        viewModel: LibraryListViewModel,
        presenter: UIKitPresentationCoordinator,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.usesSplitLayout = UIDevice.current.userInterfaceIdiom == .pad

        if usesSplitLayout {
            let primary = UINavigationController()
            let detail = UINavigationController()
            let split = UISplitViewController(style: .doubleColumn)
            split.preferredDisplayMode = .oneBesideSecondary
            split.viewControllers = [primary, detail]
            self.primaryNavigationController = primary
            self.detailNavigationController = detail
            self.compactNavigationController = nil
            self.rootViewController = split
        } else {
            let navigation = UINavigationController()
            self.compactNavigationController = navigation
            self.primaryNavigationController = nil
            self.detailNavigationController = nil
            self.rootViewController = navigation
        }

        configureRoot(tab: .library)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        installRoot()
    }

    func navigate(_ route: LibraryNavigationRoute) {
        switch route {
        case .home:
            popToRoot()
        case .openLibrary(let libraryID, let folderID):
            openLibrary(libraryID, folderID: folderID)
        case .openFolder(let descriptor, let folderID):
            openFolder(descriptor, folderID: folderID)
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
        }
    }

    func pop() {
        activeNavigationController?.popViewController(animated: true)
    }

    private var activeNavigationController: UINavigationController? {
        compactNavigationController ?? detailNavigationController
    }

    private func installRoot() {
        let root = makeHostingController(
            LibraryHomeView(
                viewModel: viewModel,
                dependencies: dependencies
            )
            .background(Color.surfaceGrouped.ignoresSafeArea()),
            title: "Library"
        )
        root.navigationItem.largeTitleDisplayMode = .always

        if let compactNavigationController {
            compactNavigationController.setViewControllers([root], animated: false)
        } else {
            primaryNavigationController?.setViewControllers([root], animated: false)
            showPlaceholder()
        }
    }

    private func openLibrary(_ libraryID: UUID, folderID: Int64?) {
        viewModel.reload()
        guard let item = viewModel.items.first(where: { $0.id == libraryID }) else {
            showUnavailable(title: "Library Unavailable", message: "This library is no longer available on this device.")
            return
        }

        selectedLibraryID = item.id
        UserDefaults.standard.set(item.id.uuidString, forKey: "libraryHome.selectedLibraryID")
        let resolvedFolderID = folderID ?? LibraryBrowserView.lastOpenedFolderID(for: item.id)
        let controller = makeLibraryBrowser(descriptor: item.descriptor, folderID: resolvedFolderID)

        if let compactNavigationController {
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                animated: true
            )
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private func openFolder(_ descriptor: LibraryDescriptor, folderID: Int64) {
        let controller = makeLibraryBrowser(descriptor: descriptor, folderID: folderID)
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: true)
        } else if let detailNavigationController {
            detailNavigationController.pushViewController(controller, animated: true)
        }
    }

    private func pushLibraryDetail<Content: View>(_ view: Content, title: String) {
        let controller = makeHostingController(view, title: title)
        controller.navigationItem.largeTitleDisplayMode = .never
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
            title: descriptor.name
        )
        controller.navigationItem.largeTitleDisplayMode = .never
        return controller
    }

    private func showPlaceholder() {
        let placeholder = makeHostingController(
            LibraryHomeDetailPlaceholder(
                itemCount: viewModel.items.count,
                onAddLibrary: { [weak self] in
                    self?.presenter.presentSheet(
                        .content(
                            id: "library.create",
                            content: AnyView(
                                LibraryCreateSheet { proposedName in
                                    guard let self,
                                          let libraryID = self.viewModel.createLibrary(named: proposedName)
                                    else {
                                        return false
                                    }

                                    self.presenter.dismissSheet()
                                    self.openLibrary(libraryID, folderID: nil)
                                    return true
                                }
                            )
                        )
                    )
                }
            ),
            title: "Library"
        )
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
            selectedImage: nil
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
        activeNavigationController?.navigationBar.prefersLargeTitles = true
        primaryNavigationController?.navigationBar.prefersLargeTitles = true
        detailNavigationController?.navigationBar.prefersLargeTitles = true
    }
}

@MainActor
private final class BrowseTabCoordinator: RootTabChildCoordinator {
    let rootViewController: UIViewController

    private let dependencies: AppDependencies
    private let viewModel: RemoteServerListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let usesSplitLayout: Bool
    private let compactNavigationController: UINavigationController?
    private let primaryNavigationController: UINavigationController?
    private let detailNavigationController: UINavigationController?
    private var editorDraft: RemoteServerEditorDraft?

    init(
        dependencies: AppDependencies,
        viewModel: RemoteServerListViewModel,
        presenter: UIKitPresentationCoordinator,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.usesSplitLayout = UIDevice.current.userInterfaceIdiom == .pad

        if usesSplitLayout {
            let primary = UINavigationController()
            let detail = UINavigationController()
            let split = UISplitViewController(style: .doubleColumn)
            split.preferredDisplayMode = .oneBesideSecondary
            split.viewControllers = [primary, detail]
            self.primaryNavigationController = primary
            self.detailNavigationController = detail
            self.compactNavigationController = nil
            self.rootViewController = split
        } else {
            let navigation = UINavigationController()
            self.compactNavigationController = navigation
            self.primaryNavigationController = nil
            self.detailNavigationController = nil
            self.rootViewController = navigation
        }

        configureRoot(tab: .browse)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        installRoot()
    }

    func navigate(_ route: BrowseNavigationRoute) {
        switch route {
        case .home:
            popToRoot()
        case .serverDetail(let profileID):
            showServerDetail(profileID)
        case .serverBrowser(let profileID, let path):
            showServerBrowser(profileID, path: path)
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

    private func installRoot() {
        let root = makeHostingController(
            BrowseHomeView(
                dependencies: dependencies,
                viewModel: viewModel,
                editorDraft: editorDraftBinding
            )
            .background(Color.surfaceGrouped.ignoresSafeArea()),
            title: "Browse"
        )
        root.navigationItem.largeTitleDisplayMode = .always

        if let compactNavigationController {
            compactNavigationController.setViewControllers([root], animated: false)
        } else {
            primaryNavigationController?.setViewControllers([root], animated: false)
            showPlaceholder()
        }
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
                return AppAlertState(title: "Unable to Save", message: "The app navigation coordinator is unavailable.")
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

    private func showServerDetail(_ profileID: UUID) {
        viewModel.load()
        guard let profile = profile(for: profileID) else {
            showUnavailable(title: "Server Unavailable", message: "This server is no longer available on this device.")
            return
        }

        persistSelection("server:\(profileID.uuidString)")
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
        setPrimaryDestination(controller)
    }

    private func showServerBrowser(_ profileID: UUID, path: String?) {
        viewModel.load()
        guard let profile = profile(for: profileID) else {
            showUnavailable(title: "Server Unavailable", message: "This server is no longer available on this device.")
            return
        }

        let controller = makeHostingController(
            RemoteServerBrowserView(
                profile: profile,
                currentPath: path,
                dependencies: dependencies
            ),
            title: profile.displayTitle
        )
        controller.navigationItem.largeTitleDisplayMode = .never
        pushOrSetDetail(controller)
    }

    private func showSavedFolders(profileID: UUID?) {
        let focusedProfile: RemoteServerProfile?
        if let profileID {
            focusedProfile = profile(for: profileID)
        } else {
            focusedProfile = nil
        }
        persistSelection(profileID.map { "saved-folders:\($0.uuidString)" } ?? "saved-folders")
        let controller = makeHostingController(
            SavedRemoteFoldersView(dependencies: dependencies, focusedProfile: focusedProfile),
            title: "Saved Folders"
        )
        controller.navigationItem.largeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.never
        setPrimaryDestination(controller)
    }

    private func showOfflineShelf(profileID: UUID?) {
        let focusedProfile: RemoteServerProfile?
        if let profileID {
            focusedProfile = profile(for: profileID)
        } else {
            focusedProfile = nil
        }
        persistSelection(profileID.map { "offline-shelf:\($0.uuidString)" } ?? "offline-shelf")
        let controller = makeHostingController(
            RemoteOfflineShelfView(dependencies: dependencies, focusedProfile: focusedProfile),
            title: "Offline Shelf"
        )
        controller.navigationItem.largeTitleDisplayMode = UINavigationItem.LargeTitleDisplayMode.never
        setPrimaryDestination(controller)
    }

    private func setPrimaryDestination(_ controller: UIViewController) {
        if let compactNavigationController {
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                animated: true
            )
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private func pushOrSetDetail(_ controller: UIViewController) {
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: true)
        } else if let detailNavigationController {
            if detailNavigationController.viewControllers.isEmpty {
                detailNavigationController.setViewControllers([controller], animated: false)
            } else {
                detailNavigationController.pushViewController(controller, animated: true)
            }
        }
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
            title: "Browse"
        )
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

    private func persistSelection(_ value: String) {
        UserDefaults.standard.set(value, forKey: AppNavigationStorageKeys.browseHomeSelection)
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
            selectedImage: nil
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
        activeNavigationController?.navigationBar.prefersLargeTitles = true
        primaryNavigationController?.navigationBar.prefersLargeTitles = true
        detailNavigationController?.navigationBar.prefersLargeTitles = true
    }
}

@MainActor
private final class SettingsTabCoordinator: RootTabChildCoordinator {
    let rootViewController: UIViewController

    private let dependencies: AppDependencies
    private let viewModel: LibraryListViewModel
    private let presenter: UIKitPresentationCoordinator
    private let navigator = AppNavigator()
    private let usesSplitLayout: Bool
    private let compactNavigationController: UINavigationController?
    private let primaryNavigationController: UINavigationController?
    private let detailNavigationController: UINavigationController?

    init(
        dependencies: AppDependencies,
        viewModel: LibraryListViewModel,
        presenter: UIKitPresentationCoordinator,
        rootNavigate: @escaping (AppNavigationRoute) -> Void,
        selectTab: @escaping (AppRootTab) -> Void
    ) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        self.presenter = presenter
        self.usesSplitLayout = UIDevice.current.userInterfaceIdiom == .pad

        if usesSplitLayout {
            let primary = UINavigationController()
            let detail = UINavigationController()
            let split = UISplitViewController(style: .doubleColumn)
            split.preferredDisplayMode = .oneBesideSecondary
            split.viewControllers = [primary, detail]
            self.primaryNavigationController = primary
            self.detailNavigationController = detail
            self.compactNavigationController = nil
            self.rootViewController = split
        } else {
            let navigation = UINavigationController()
            self.compactNavigationController = navigation
            self.primaryNavigationController = nil
            self.detailNavigationController = nil
            self.rootViewController = navigation
        }

        configureRoot(tab: .settings)
        navigator.update(
            navigate: { route in rootNavigate(route) },
            selectTab: selectTab,
            pop: { [weak self] in self?.pop() }
        )
        installRoot()
    }

    func navigate(_ route: SettingsNavigationRoute) {
        switch route {
        case .overview, .reading, .remote, .storage, .about:
            showPane(route)
        case .remoteNetwork:
            pushOrSetDetail(makeHostingController(RemoteNetworkSettingsView(), title: "Network"))
        case .remoteCache:
            pushOrSetDetail(
                makeHostingController(
                    RemoteCacheSettingsView(dependencies: dependencies),
                    title: "Cache Management"
                )
            )
        }
    }

    func pop() {
        activeNavigationController?.popViewController(animated: true)
    }

    private var activeNavigationController: UINavigationController? {
        compactNavigationController ?? detailNavigationController
    }

    private func installRoot() {
        let root = makeHostingController(
            SettingsHomeView(viewModel: viewModel, dependencies: dependencies),
            title: "Settings"
        )
        root.navigationItem.largeTitleDisplayMode = .always

        if let compactNavigationController {
            compactNavigationController.setViewControllers([root], animated: false)
        } else {
            primaryNavigationController?.setViewControllers([root], animated: false)
            showPane(.overview)
        }
    }

    private func showPane(_ route: SettingsNavigationRoute) {
        UserDefaults.standard.set(route.storageValue, forKey: AppNavigationStorageKeys.settingsHomeSelectedPane)
        let controller = makeHostingController(
            SettingsPaneContentView(
                pane: route.settingsPane,
                viewModel: viewModel,
                dependencies: dependencies
            ),
            title: route.settingsPane.titleString
        )
        controller.navigationItem.largeTitleDisplayMode = .never

        if let compactNavigationController {
            compactNavigationController.setViewControllers(
                [compactNavigationController.viewControllers.first, controller].compactMap { $0 },
                animated: true
            )
        } else {
            detailNavigationController?.setViewControllers([controller], animated: false)
        }
    }

    private func pushOrSetDetail(_ controller: UIViewController) {
        controller.navigationItem.largeTitleDisplayMode = .never
        if let compactNavigationController {
            compactNavigationController.pushViewController(controller, animated: true)
        } else if let detailNavigationController {
            detailNavigationController.pushViewController(controller, animated: true)
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
            selectedImage: nil
        )
        rootViewController.view.backgroundColor = .systemGroupedBackground
        activeNavigationController?.navigationBar.prefersLargeTitles = true
        primaryNavigationController?.navigationBar.prefersLargeTitles = true
        detailNavigationController?.navigationBar.prefersLargeTitles = true
    }
}

extension AppRootTab {
    var title: String {
        switch self {
        case .library:
            return "Library"
        case .browse:
            return "Browse"
        case .settings:
            return "Settings"
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
            UIKeyCommand(input: "1", modifierFlags: .command, action: #selector(selectLibraryTab)),
            UIKeyCommand(input: "2", modifierFlags: .command, action: #selector(selectBrowseTab)),
            UIKeyCommand(input: "3", modifierFlags: .command, action: #selector(selectSettingsTab))
        ]
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

final class PassthroughOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView === self || hitView === subviews.first {
            return nil
        }

        return hitView
    }
}
