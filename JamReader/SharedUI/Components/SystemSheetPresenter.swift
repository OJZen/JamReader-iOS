import SwiftUI
import UIKit

struct SystemSheetPresenter<Item: Identifiable, SheetContent: View>: View {
    @Binding var item: Item?
    var onDismiss: (() -> Void)? = nil
    @State private var coordinator = WindowBackedSystemSheetCoordinator()
    @ViewBuilder var content: (Item) -> SheetContent

    var body: some View {
        Color.clear
            .onAppear {
                synchronizePresentation()
            }
            .onChange(of: item?.id) { _, _ in
                synchronizePresentation()
            }
    }

    @MainActor
    private func synchronizePresentation() {
        if let item {
            coordinator.present(
                itemID: item.id,
                onDismiss: {
                    self.item = nil
                    onDismiss?()
                },
                content: AnyView(content(item))
            )
        } else {
            coordinator.dismiss()
        }
    }
}

@MainActor
final class WindowBackedSystemSheetCoordinator {
    private enum PresentationTiming {
        static let deferredPresentationDelay: DispatchTimeInterval = .milliseconds(120)
        static let interactionUnlockDelay: DispatchTimeInterval = .milliseconds(350)
    }

    private var requestedItemID: AnyHashable?
    private var presentedItemID: AnyHashable?
    private weak var presentedController: DismissTrackingSheetHostingController<AnyView>?
    private var dismissalHandler: (() -> Void)?
    private weak var baseWindow: UIWindow?
    private var presentationWindow: SheetPresentationWindow?
    private var pendingPresentationWorkItem: DispatchWorkItem?

    func present<ItemID: Hashable>(
        itemID: ItemID,
        onDismiss: @escaping () -> Void,
        content: AnyView
    ) {
        let anyItemID = AnyHashable(itemID)
        dismissalHandler = onDismiss
        requestedItemID = anyItemID

        if let presentedController, presentedController.presentingViewController != nil {
            if presentedItemID == anyItemID {
                return
            }

            presentedController.dismiss(animated: false)
            self.presentedController = nil
            self.presentedItemID = nil
            pendingPresentationWorkItem?.cancel()
            pendingPresentationWorkItem = nil

            DispatchQueue.main.async { [weak self] in
                self?.present(itemID: itemID, onDismiss: onDismiss, content: content)
            }
            return
        }

        pendingPresentationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performPresentation(
                itemID: anyItemID,
                content: content
            )
        }
        pendingPresentationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + PresentationTiming.deferredPresentationDelay,
            execute: workItem
        )
    }

    func dismiss() {
        requestedItemID = nil
        presentedItemID = nil
        pendingPresentationWorkItem?.cancel()
        pendingPresentationWorkItem = nil

        if let presentedController, presentedController.presentingViewController != nil {
            presentedController.dismiss(animated: true)
        } else {
            presentationWindow?.isUserInteractionEnabled = true
            hidePresentationWindowIfNeeded()
        }

        presentedController = nil
    }

    private func performPresentation(
        itemID: AnyHashable,
        content: AnyView
    ) {
        pendingPresentationWorkItem = nil

        guard requestedItemID == itemID else {
            return
        }

        guard let window = ensurePresentationWindow(),
              let rootViewController = window.rootViewController else {
            return
        }

        window.isUserInteractionEnabled = false

        let hostingController = DismissTrackingSheetHostingController(rootView: content)
        hostingController.modalPresentationStyle = .automatic
        hostingController.onDismiss = { [weak self] in
            guard let self else {
                return
            }

            self.presentedController = nil
            self.presentedItemID = nil
            self.requestedItemID = nil
            self.pendingPresentationWorkItem?.cancel()
            self.pendingPresentationWorkItem = nil
            self.presentationWindow?.isUserInteractionEnabled = true
            self.hidePresentationWindowIfNeeded()

            let dismissalHandler = self.dismissalHandler
            DispatchQueue.main.async {
                dismissalHandler?()
            }
        }

        configure(controller: hostingController, traits: rootViewController.traitCollection)
        presentedItemID = itemID
        presentedController = hostingController

        rootViewController.present(hostingController, animated: true) { [weak self, weak window, weak hostingController] in
            DispatchQueue.main.asyncAfter(deadline: .now() + PresentationTiming.interactionUnlockDelay) {
                guard let self,
                      let window,
                      let hostingController,
                      self.presentedController === hostingController else {
                    return
                }

                window.isUserInteractionEnabled = true
            }
        }
    }

    private func ensurePresentationWindow() -> SheetPresentationWindow? {
        if let presentationWindow {
            return presentationWindow
        }

        guard let scene = foregroundWindowScene() else {
            return nil
        }

        baseWindow = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first

        let window = SheetPresentationWindow(windowScene: scene)
        window.rootViewController = SheetWindowRootViewController()
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()

        presentationWindow = window
        return window
    }

    private func hidePresentationWindowIfNeeded() {
        guard let presentationWindow else {
            return
        }

        guard presentationWindow.rootViewController?.presentedViewController == nil else {
            return
        }

        presentationWindow.isUserInteractionEnabled = true
        presentationWindow.isHidden = true
        self.presentationWindow = nil
        baseWindow?.makeKey()
        baseWindow = nil
    }

    private func foregroundWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: {
                $0.activationState == .foregroundActive
                    || $0.activationState == .foregroundInactive
            })
    }

    private func configure(
        controller: UIViewController,
        traits: UITraitCollection
    ) {
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

final class SheetPresentationWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SheetWindowRootViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

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
