import SwiftUI
import UIKit

@MainActor
final class UIKitPresentationCoordinator {
    private let dependencies: AppDependencies
    private weak var rootViewController: UIViewController?
    private var readerTransitionDelegate: (any UIViewControllerTransitioningDelegate)?
    private weak var presentedReaderController: UIViewController?
    private weak var presentedSheetController: DismissTrackingSheetHostingController<AnyView>?
    private var presentedSheetID: AnyHashable?

    init(dependencies: AppDependencies, rootViewController: UIViewController? = nil) {
        self.dependencies = dependencies
        self.rootViewController = rootViewController
    }

    func attach(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
    }

    func presentReader(_ route: ReaderPresentationRoute) {
        let request: ComicOpenRequest
        let sourceFrame: CGRect
        let previewImage: UIImage?
        let transitionStyle: ReaderHeroTransitionStyle
        let onDismiss: (() -> Void)?

        switch route {
        case .local(let presentation):
            request = .library(
                ComicLibraryOpenRequest(
                    descriptor: presentation.descriptor,
                    comic: presentation.comic,
                    navigationContext: presentation.navigationContext,
                    onComicUpdated: presentation.onComicUpdated
                )
            )
            sourceFrame = presentation.sourceFrame
            previewImage = presentation.previewImage
            transitionStyle = presentation.transitionStyle
            onDismiss = presentation.onDismiss
        case .remote(let presentation):
            request = .remote(
                ComicRemoteOpenRequest(
                    profile: presentation.profile,
                    item: presentation.item,
                    openMode: presentation.openMode,
                    referenceOverride: presentation.referenceOverride
                )
            )
            sourceFrame = presentation.sourceFrame
            previewImage = presentation.previewImage
            transitionStyle = presentation.transitionStyle
            onDismiss = presentation.onDismiss
        }

        let content = AnyView(
            ComicReaderView(
                request: request,
                dependencies: dependencies,
                openingPreviewImage: previewImage
            )
                .environment(\.appPresenter, self)
        )

        presentReader(
            content: content,
            sourceFrame: sourceFrame,
            previewImage: previewImage,
            transitionStyle: transitionStyle,
            onDismiss: onDismiss
        )
    }

    func presentSheet(_ route: AppSheetRoute) {
        presentSheet(id: route.id, content: route.content, onDismiss: route.onDismiss)
    }

    func presentSheet(id: AnyHashable, content: AnyView, onDismiss: (() -> Void)? = nil) {
        guard let presenter = topPresenter() else {
            return
        }

        if let presentedSheetController {
            guard presentedSheetID != id else {
                presentedSheetController.rootView = content
                presentedSheetController.onDismiss = sheetDismissHandler(onDismiss)
                return
            }

            self.presentedSheetController = nil
            presentedSheetID = nil
            presentedSheetController.dismiss(animated: false) { [weak self] in
                self?.presentSheet(id: id, content: content, onDismiss: onDismiss)
            }
            return
        }

        let hostingController = DismissTrackingSheetHostingController(rootView: content)
        hostingController.modalPresentationStyle = .automatic
        hostingController.onDismiss = sheetDismissHandler(onDismiss)

        configureSheet(hostingController, traits: presenter.traitCollection)
        presentedSheetID = id
        presentedSheetController = hostingController
        presenter.present(hostingController, animated: true)
    }

    private func sheetDismissHandler(_ onDismiss: (() -> Void)?) -> () -> Void {
        { [weak self] in
            self?.presentedSheetController = nil
            self?.presentedSheetID = nil
            onDismiss?()
        }
    }

    func dismissSheet() {
        guard let presentedSheetController else {
            return
        }

        self.presentedSheetController = nil
        presentedSheetID = nil
        presentedSheetController.dismiss(animated: true)
    }

    private func presentReader(
        content: AnyView,
        sourceFrame: CGRect,
        previewImage: UIImage?,
        transitionStyle: ReaderHeroTransitionStyle,
        onDismiss: (() -> Void)?
    ) {
        if let presentedReaderController {
            self.presentedReaderController = nil
            readerTransitionDelegate = nil
            presentedReaderController.dismiss(animated: false) { [weak self] in
                self?.presentReader(
                    content: content,
                    sourceFrame: sourceFrame,
                    previewImage: previewImage,
                    transitionStyle: transitionStyle,
                    onDismiss: onDismiss
                )
            }
            return
        }

        guard let presenter = rootViewController ?? topPresenter() else {
            return
        }

        let transitionDelegate = HeroTransitionDelegate(
            sourceFrame: sourceFrame,
            previewImage: previewImage,
            style: transitionStyle
        )
        readerTransitionDelegate = transitionDelegate

        let hostingController = DismissTrackingReaderHostingController(rootView: content)
        hostingController.modalPresentationStyle = .custom
        hostingController.modalPresentationCapturesStatusBarAppearance = true
        hostingController.transitioningDelegate = transitionDelegate
        hostingController.onDismiss = { [weak self] in
            self?.presentedReaderController = nil
            self?.readerTransitionDelegate = nil
            onDismiss?()
        }

        presentedReaderController = hostingController
        presenter.present(hostingController, animated: true)
    }

    private func topPresenter() -> UIViewController? {
        guard let rootViewController else {
            return nil
        }

        var presenter = rootViewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        if let tabBarController = presenter as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            presenter = selected
        }

        if let navigationController = presenter as? UINavigationController,
           let visible = navigationController.visibleViewController {
            presenter = visible
        }

        if let splitViewController = presenter as? UISplitViewController,
           let last = splitViewController.viewControllers.last {
            presenter = last
        }

        if let navigationController = presenter as? UINavigationController,
           let visible = navigationController.visibleViewController {
            presenter = visible
        }

        return presenter
    }

    private func configureSheet(_ controller: UIViewController, traits: UITraitCollection) {
        guard let sheet = controller.sheetPresentationController else {
            return
        }

        sheet.prefersGrabberVisible = true

        if traits.horizontalSizeClass == .compact {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
        }
    }
}

final class DismissTrackingReaderHostingController<Content: View>: UIHostingController<Content> {
    var onDismiss: (() -> Void)?
    private var hasReportedDismissal = false

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isBeingDismissed || isMovingFromParent {
            notifyDismissIfNeeded()
        }
    }

    private func notifyDismissIfNeeded() {
        guard !hasReportedDismissal else {
            return
        }

        hasReportedDismissal = true
        onDismiss?()
    }
}
