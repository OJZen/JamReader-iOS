import SwiftUI
import UIKit

extension View {
    /// While `isBlocked`, a swipe down does not close the sheet; `onAttempt`
    /// runs instead so the page can ask "Discard Changes / Keep Editing".
    func sheetDismissGuard(isBlocked: Bool, onAttempt: @escaping () -> Void) -> some View {
        background {
            SheetDismissGuardBridge(isBlocked: isBlocked, onAttempt: onAttempt)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct SheetDismissGuardBridge: UIViewControllerRepresentable {
    let isBlocked: Bool
    let onAttempt: () -> Void

    func makeCoordinator() -> DismissAttemptProxy {
        DismissAttemptProxy()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let proxy = context.coordinator
        proxy.onAttempt = onAttempt
        let isBlocked = isBlocked

        DispatchQueue.main.async {
            // The sheet's root is the presented controller that owns the presentation.
            var sheetRoot = controller
            while let parent = sheetRoot.parent {
                sheetRoot = parent
            }

            sheetRoot.isModalInPresentation = isBlocked
            if let presentationController = sheetRoot.presentationController,
               !(presentationController.delegate is DismissAttemptProxy) {
                proxy.original = presentationController.delegate
                presentationController.delegate = proxy
            }
        }
    }
}

/// Forwards every delegate call to the presentation's original delegate and
/// adds the dismiss-attempt callback.
private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var original: UIAdaptivePresentationControllerDelegate?
    var onAttempt: () -> Void = {}

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if original?.responds(to: aSelector) == true {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
        onAttempt()
    }
}
