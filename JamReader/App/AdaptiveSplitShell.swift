import Observation
import SwiftUI
import UIKit

/// Whether a tab's sidebar is on screen beside its content. Pages read it to
/// leave out entries the sidebar already lists.
@MainActor
@Observable
final class SplitLayoutState {
    var isSidebarVisible: Bool

    init(isSidebarVisible: Bool) {
        self.isSidebarVisible = isSidebarVisible
    }
}

/// A tab's split view, always created. Compact width shows the compact column
/// (the iPhone stack: home, then pages); regular width shows the sidebar beside
/// the detail stack. The decision follows the window width, not the device.
///
/// Opening, closing, rotating or resizing moves the same page controllers
/// between the two stacks, so the hierarchy, scroll positions and page state
/// carry over. See docs/design-system/06-iphone-duo.md.
@MainActor
final class AdaptiveSplitShell: NSObject, UISplitViewControllerDelegate {
    static let placeholderIdentifier = "adaptiveSplit.placeholder"

    let splitViewController = UISplitViewController(style: .doubleColumn)
    let primaryNavigationController = UINavigationController()
    let detailNavigationController = UINavigationController()
    let compactNavigationController = UINavigationController()
    let layoutState: SplitLayoutState

    /// Called after expanding when no page came over from the compact stack.
    var onExpandWithoutDetail: (() -> Void)?

    private(set) var isCollapsed: Bool

    init(initiallyCollapsed: Bool) {
        isCollapsed = initiallyCollapsed
        layoutState = SplitLayoutState(isSidebarVisible: !initiallyCollapsed)
        super.init()

        splitViewController.preferredDisplayMode = .oneBesideSecondary
        splitViewController.setViewController(primaryNavigationController, for: .primary)
        splitViewController.setViewController(detailNavigationController, for: .secondary)
        splitViewController.setViewController(compactNavigationController, for: .compact)
        splitViewController.delegate = self
        for navigationController in [primaryNavigationController, detailNavigationController, compactNavigationController] {
            navigationController.navigationBar.prefersLargeTitles = true
        }
    }

    /// The stack that shows pages right now.
    var activeNavigationController: UINavigationController {
        isCollapsed ? compactNavigationController : detailNavigationController
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        setCollapsed(true)
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        setCollapsed(false)
    }

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        .compact
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else {
            return
        }

        isCollapsed = collapsed
        if collapsed {
            let pages = detailNavigationController.viewControllers.filter {
                $0.restorationIdentifier != Self.placeholderIdentifier
            }
            detailNavigationController.setViewControllers([], animated: false)
            let home = Array(compactNavigationController.viewControllers.prefix(1))
            compactNavigationController.setViewControllers(home + pages, animated: false)
        } else {
            let pages = Array(compactNavigationController.viewControllers.dropFirst())
            let home = Array(compactNavigationController.viewControllers.prefix(1))
            compactNavigationController.setViewControllers(home, animated: false)
            if pages.isEmpty {
                onExpandWithoutDetail?()
            } else {
                detailNavigationController.setViewControllers(pages, animated: false)
            }
        }
        layoutState.isSidebarVisible = !collapsed
    }
}

/// True when the window is compact width, before the split view has traits.
@MainActor
func adaptiveSplitStartsCollapsed(in windowScene: UIWindowScene) -> Bool {
    windowScene.traitCollection.horizontalSizeClass != .regular
}
