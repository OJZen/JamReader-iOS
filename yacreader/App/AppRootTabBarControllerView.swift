import SwiftUI
import UIKit

struct AppRootTabBarControllerView: UIViewControllerRepresentable {
    @Binding var selection: AppRootTab
    @Binding var tabBarHeight: CGFloat

    let libraryRoot: AnyView
    let browseRoot: AnyView
    let settingsRoot: AnyView

    func makeCoordinator() -> AppRootTabBarCoordinator {
        AppRootTabBarCoordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> RootTabBarController {
        let controller = RootTabBarController()
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        controller.onTabBarHeightChange = { height in
            context.coordinator.updateTabBarHeight(height)
        }

        if #available(iOS 18.0, *) {
            controller.mode = .tabBar
        }

        controller.setViewControllers(
            [
                makeHostingController(
                    rootView: libraryRoot,
                    tab: .library
                ),
                makeHostingController(
                    rootView: browseRoot,
                    tab: .browse
                ),
                makeHostingController(
                    rootView: settingsRoot,
                    tab: .settings
                )
            ],
            animated: false
        )
        controller.selectedIndex = selection.index

        return controller
    }

    func updateUIViewController(_ uiViewController: RootTabBarController, context: Context) {
        context.coordinator.parent = self
        uiViewController.onTabBarHeightChange = { height in
            context.coordinator.updateTabBarHeight(height)
        }
        updateHostedControllers(in: uiViewController)

        let desiredIndex = selection.index
        if uiViewController.selectedIndex != desiredIndex {
            uiViewController.selectedIndex = desiredIndex
        }

        if #available(iOS 18.0, *) {
            uiViewController.mode = .tabBar
        }
    }

    private func updateHostedControllers(in controller: RootTabBarController) {
        let roots = [
            (libraryRoot, AppRootTab.library),
            (browseRoot, AppRootTab.browse),
            (settingsRoot, AppRootTab.settings)
        ]

        guard let hostedControllers = controller.viewControllers as? [RootTabHostingController],
              hostedControllers.count == roots.count else {
            return
        }

        for (host, payload) in zip(hostedControllers, roots) {
            host.rootView = payload.0
            host.tabBarItem.title = payload.1.title
            host.tabBarItem.image = UIImage(systemName: payload.1.systemImage)
        }
    }

    private func makeHostingController(
        rootView: AnyView,
        tab: AppRootTab
    ) -> UIViewController {
        let controller = RootTabHostingController(rootView: rootView)
        controller.view.backgroundColor = .clear
        controller.tabBarItem = UITabBarItem(
            title: tab.title,
            image: UIImage(systemName: tab.systemImage),
            selectedImage: nil
        )
        return controller
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
    var onTabBarHeightChange: ((CGFloat) -> Void)?
    private var lastReportedTabBarHeight: CGFloat = 0

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let height = tabBar.bounds.height
        guard abs(height - lastReportedTabBarHeight) > 0.5 else {
            return
        }

        lastReportedTabBarHeight = height
        onTabBarHeightChange?(height)
    }
}

final class RootTabHostingController: UIHostingController<AnyView> {}

final class AppRootTabBarCoordinator: NSObject, UITabBarControllerDelegate {
    var parent: AppRootTabBarControllerView

    init(parent: AppRootTabBarControllerView) {
        self.parent = parent
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        guard let selectedTab = AppRootTab(index: tabBarController.selectedIndex) else {
            return
        }

        if parent.selection != selectedTab {
            parent.selection = selectedTab
        }
    }

    func updateTabBarHeight(_ height: CGFloat) {
        guard abs(parent.tabBarHeight - height) > 0.5 else {
            return
        }

        DispatchQueue.main.async {
            self.parent.tabBarHeight = height
        }
    }
}
