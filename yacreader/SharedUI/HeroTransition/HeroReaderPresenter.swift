import SwiftUI
import UIKit

/// Drop-in replacement for `.fullScreenCover(item:)` that presents the reader
/// using `modalPresentationStyle = .overFullScreen` so the browser remains
/// rendered and visible behind the reader during pull-down-to-dismiss, plus a
/// hero zoom-from-cell open animation via `HeroTransitionDelegate`.
///
/// Place this as a `.background()` modifier on the root browser view.
///
/// ```swift
/// .background(
///     HeroReaderPresenter(item: $presentedComic, sourceFrame: heroSourceFrame) { presentation in
///         ComicReaderView(...)
///     }
/// )
/// ```
struct HeroReaderPresenter<Item: Identifiable, Content: View>: UIViewControllerRepresentable {
    @Binding var item: Item?
    var sourceFrame: CGRect
    var previewImage: UIImage? = nil
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: (Item) -> Content

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var parent: HeroReaderPresenter
        /// The item ID that is currently being presented (or was last presented).
        var lastPresentedItemID: Item.ID?
        /// Strong reference so the delegate is not deallocated mid-transition.
        var transitionDelegate: HeroTransitionDelegate?

        init(_ parent: HeroReaderPresenter) {
            self.parent = parent
        }

        /// Called on the main queue after each SwiftUI update.
        func sync(with presenterVC: _HeroPresenterViewController) {
            guard presenterVC.view.window != nil else { return }

            if let item = parent.item {
                guard
                    item.id != lastPresentedItemID,
                    presenterVC.presentedViewController == nil
                else { return }

                lastPresentedItemID = item.id

                let delegate = HeroTransitionDelegate(
                    sourceFrame: parent.sourceFrame,
                    previewImage: parent.previewImage
                )
                transitionDelegate = delegate

                let hostingVC = DismissTrackingHostingController(rootView: parent.content(item))
                hostingVC.modalPresentationStyle = .overFullScreen
                hostingVC.modalPresentationCapturesStatusBarAppearance = true
                hostingVC.transitioningDelegate = delegate
                hostingVC.onDismiss = { [weak self] in
                    guard let self else { return }
                    self.lastPresentedItemID = nil
                    self.parent.item = nil
                    self.parent.onDismiss?()
                }

                presenterVC.present(hostingVC, animated: true)
            } else {
                lastPresentedItemID = nil
                if presenterVC.presentedViewController != nil {
                    presenterVC.dismiss(animated: true)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> _HeroPresenterViewController {
        _HeroPresenterViewController()
    }

    func updateUIViewController(_ vc: _HeroPresenterViewController, context: Context) {
        context.coordinator.parent = self
        // Defer to the next run-loop tick so the view is fully in the hierarchy
        // before we attempt to call present().
        DispatchQueue.main.async {
            context.coordinator.sync(with: vc)
        }
    }
}

// MARK: - Supporting types

/// A transparent UIViewController that acts as the presentation host.
final class _HeroPresenterViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
}

/// Subclass of UIHostingController that detects when the presented reader is
/// dismissed and fires a callback to clear the binding.
final class DismissTrackingHostingController<Content: View>: UIHostingController<Content> {
    var onDismiss: (() -> Void)?

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Must be clear so the browser (kept alive by .overFullScreen) shows
        // through when SwiftUI's content becomes transparent during dismiss.
        view.backgroundColor = .clear
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            onDismiss?()
        }
    }
}
