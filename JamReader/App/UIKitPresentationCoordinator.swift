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
        let content: AnyView
        let sourceFrame: CGRect
        let previewImage: UIImage?
        let transitionStyle: ReaderHeroTransitionStyle
        let onDismiss: (() -> Void)?

        switch route {
        case .local(let presentation):
            content = AnyView(
                ComicReaderView(
                    descriptor: presentation.descriptor,
                    comic: presentation.comic,
                    navigationContext: presentation.navigationContext,
                    onComicUpdated: presentation.onComicUpdated,
                    dependencies: dependencies
                )
                .environment(\.appPresenter, self)
            )
            sourceFrame = presentation.sourceFrame
            previewImage = presentation.previewImage
            transitionStyle = presentation.transitionStyle
            onDismiss = presentation.onDismiss
        case .remote(let presentation):
            content = AnyView(
                RemoteComicLoadingView(
                    profile: presentation.profile,
                    item: presentation.item,
                    dependencies: dependencies,
                    openMode: presentation.openMode,
                    referenceOverride: presentation.referenceOverride
                )
                .environment(\.appPresenter, self)
            )
            sourceFrame = presentation.sourceFrame
            previewImage = presentation.previewImage
            transitionStyle = presentation.transitionStyle
            onDismiss = presentation.onDismiss
        }

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

        let transitionDelegate = ReaderSlideTransitionDelegate()
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

private final class ReaderSlideTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        ReaderSlidePresentTransition()
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        ReaderSlideDismissTransition()
    }
}

private final class ReaderSlidePresentTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.16 : 0.30
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let toViewController = transitionContext.viewController(forKey: .to),
            let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toViewController)
        toView.frame = finalFrame
        toView.backgroundColor = .black
        container.addSubview(toView)

        if UIAccessibility.isReduceMotionEnabled {
            toView.alpha = 0
            UIView.animate(
                withDuration: transitionDuration(using: transitionContext),
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                toView.alpha = 1
            } completion: { _ in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
            return
        }

        toView.alpha = 0.96
        toView.transform = CGAffineTransform(translationX: 0, y: finalFrame.height)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            usingSpringWithDamping: 0.95,
            initialSpringVelocity: 0.0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            toView.alpha = 1
            toView.transform = .identity
        } completion: { _ in
            toView.transform = .identity
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}

private final class ReaderSlideDismissTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.14 : 0.24
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        let finalTranslationY = max(fromView.bounds.height, transitionContext.containerView.bounds.height)

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            fromView.alpha = UIAccessibility.isReduceMotionEnabled ? 0 : 0.98
            if !UIAccessibility.isReduceMotionEnabled {
                fromView.transform = CGAffineTransform(translationX: 0, y: finalTranslationY)
            }
        } completion: { _ in
            let completed = !transitionContext.transitionWasCancelled
            if !completed {
                fromView.alpha = 1
                fromView.transform = .identity
            }
            transitionContext.completeTransition(completed)
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
