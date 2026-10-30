import UIKit
import XCTest
@testable import JamReader

@MainActor
final class AdaptiveSplitShellTests: XCTestCase {
    func testCollapsingMovesTheSamePagesOntoTheCompactStack() {
        let shell = AdaptiveSplitShell(initiallyCollapsed: false)
        let home = UIViewController()
        let library = UIViewController()
        let folder = UIViewController()
        shell.compactNavigationController.setViewControllers([home], animated: false)
        shell.detailNavigationController.setViewControllers([library, folder], animated: false)

        shell.splitViewControllerDidCollapse(shell.splitViewController)

        XCTAssertTrue(shell.isCollapsed)
        XCTAssertFalse(shell.layoutState.isSidebarVisible)
        XCTAssertTrue(shell.activeNavigationController === shell.compactNavigationController)
        XCTAssertEqual(shell.compactNavigationController.viewControllers, [home, library, folder])
        XCTAssertTrue(shell.detailNavigationController.viewControllers.isEmpty)
    }

    func testExpandingMovesThePagesBackBesideTheSidebar() {
        let shell = AdaptiveSplitShell(initiallyCollapsed: true)
        let home = UIViewController()
        let page = UIViewController()
        shell.compactNavigationController.setViewControllers([home, page], animated: false)

        shell.splitViewControllerDidExpand(shell.splitViewController)

        XCTAssertFalse(shell.isCollapsed)
        XCTAssertTrue(shell.layoutState.isSidebarVisible)
        XCTAssertEqual(shell.compactNavigationController.viewControllers, [home])
        XCTAssertEqual(shell.detailNavigationController.viewControllers, [page])
    }

    func testPlaceholderStaysBehindAndAnEmptyExpandAsksForContent() {
        let shell = AdaptiveSplitShell(initiallyCollapsed: false)
        let home = UIViewController()
        let placeholder = UIViewController()
        placeholder.restorationIdentifier = AdaptiveSplitShell.placeholderIdentifier
        shell.compactNavigationController.setViewControllers([home], animated: false)
        shell.detailNavigationController.setViewControllers([placeholder], animated: false)
        var expandRequests = 0
        shell.onExpandWithoutDetail = { expandRequests += 1 }

        shell.splitViewControllerDidCollapse(shell.splitViewController)
        XCTAssertEqual(shell.compactNavigationController.viewControllers, [home])

        shell.splitViewControllerDidExpand(shell.splitViewController)
        XCTAssertEqual(expandRequests, 1)
    }

    func testRepeatedNotificationsDoNotMovePagesTwice() {
        let shell = AdaptiveSplitShell(initiallyCollapsed: true)
        let home = UIViewController()
        let page = UIViewController()
        shell.compactNavigationController.setViewControllers([home, page], animated: false)

        shell.splitViewControllerDidCollapse(shell.splitViewController)

        XCTAssertEqual(shell.compactNavigationController.viewControllers, [home, page])
    }
}
