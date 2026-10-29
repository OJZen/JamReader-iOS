import SwiftUI
import UIKit

extension View {
    /// Hides the app's UIKit tab bar while `isHidden` and shows the navigation
    /// controller's toolbar, so the page's `.bottomBar` items take its place.
    /// Before iOS 18 the tab bar stays and the toolbar appears above it.
    func systemTabBarHidden(_ isHidden: Bool) -> some View {
        background {
            SystemTabBarVisibilityBridge(isHidden: isHidden)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct SystemTabBarVisibilityBridge: UIViewControllerRepresentable {
    let isHidden: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let isHidden = isHidden
        DispatchQueue.main.async {
            if let navigationController = controller.navigationController,
               navigationController.isToolbarHidden == isHidden {
                navigationController.setToolbarHidden(!isHidden, animated: true)
            }

            guard #available(iOS 18.0, *),
                  let tabBarController = controller.tabBarController,
                  tabBarController.isTabBarHidden != isHidden else {
                return
            }
            tabBarController.setTabBarHidden(isHidden, animated: true)
        }
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
        if let navigationController = controller.navigationController,
           !navigationController.isToolbarHidden {
            navigationController.setToolbarHidden(true, animated: true)
        }

        guard #available(iOS 18.0, *),
              let tabBarController = controller.tabBarController,
              tabBarController.isTabBarHidden else {
            return
        }
        tabBarController.setTabBarHidden(false, animated: true)
    }
}
