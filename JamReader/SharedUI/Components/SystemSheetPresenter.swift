import SwiftUI

final class DismissTrackingSheetHostingController<Content: View>: UIHostingController<Content>, UIAdaptivePresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    private var hasReportedDismissal = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentationController?.delegate = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isBeingDismissed || isMovingFromParent {
            notifyDismissIfNeeded()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        notifyDismissIfNeeded()
    }

    private func notifyDismissIfNeeded() {
        guard !hasReportedDismissal else {
            return
        }

        hasReportedDismissal = true
        onDismiss?()
    }
}
