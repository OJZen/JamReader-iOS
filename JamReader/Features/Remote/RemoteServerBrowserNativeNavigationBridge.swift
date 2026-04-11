import UIKit

final class RemoteServerBrowserNativeNavigationBridge {
    private struct HostRecord {
        weak var host: UIViewController?
        let previousExtendedLayoutIncludesOpaqueBars: Bool
    }

    private weak var trackedScrollView: UIScrollView?
    private weak var navigationController: UINavigationController?
    private var hostRecords: [HostRecord] = []

    func attach(scrollView: UIScrollView, from controller: UIViewController) {
        let hosts = navigationAppearanceHosts(for: controller)
        guard !hosts.isEmpty else {
            return
        }

        let needsReconfigure = trackedScrollView !== scrollView
            || hosts.map(ObjectIdentifier.init) != hostRecords.compactMap { record in
                record.host.map(ObjectIdentifier.init)
            }

        guard needsReconfigure else {
            return
        }

        detach()

        trackedScrollView = scrollView

        hostRecords = hosts.map { host in
            let record = HostRecord(
                host: host,
                previousExtendedLayoutIncludesOpaqueBars: host.extendedLayoutIncludesOpaqueBars
            )
            host.extendedLayoutIncludesOpaqueBars = true
            host.setContentScrollView(scrollView, for: .top)
            return record
        }

        if let navigationController = hosts.last?.navigationController {
            self.navigationController = navigationController
            navigationController.setContentScrollView(scrollView, for: .top)
        }
    }

    func detach() {
        for record in hostRecords {
            guard let host = record.host else {
                continue
            }

            host.setContentScrollView(nil, for: .top)
            host.extendedLayoutIncludesOpaqueBars = record.previousExtendedLayoutIncludesOpaqueBars
        }

        if let navigationController {
            navigationController.setContentScrollView(nil, for: .top)
        }

        trackedScrollView = nil
        self.navigationController = nil
        hostRecords = []
    }

    private func navigationAppearanceHosts(for controller: UIViewController) -> [UIViewController] {
        guard controller.navigationController != nil else {
            return []
        }

        // Keep the scroll-view bridge local to the UIKit browser controller.
        // Walking the full parent chain can reach SwiftUI hosting controllers,
        // which is where the earlier reparenting warnings came from.
        return [controller]
    }
}
