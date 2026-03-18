import SwiftUI
import UIKit

struct ReaderPageJumpOverlay: UIViewControllerRepresentable {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ReaderPageJumpHostViewController {
        let controller = ReaderPageJumpHostViewController()
        controller.view.isUserInteractionEnabled = false
        controller.onDidAppear = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else {
                return
            }

            coordinator?.presentIfNeeded(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ReaderPageJumpHostViewController, context: Context) {
        context.coordinator.update(from: self)
        context.coordinator.presentIfNeeded(from: uiViewController)
    }

    static func dismantleUIViewController(
        _ uiViewController: ReaderPageJumpHostViewController,
        coordinator: Coordinator
    ) {
        coordinator.dismissIfNeeded(animated: false)
    }

    final class Coordinator: NSObject {
        private var pageNumberText: Binding<String>
        private var currentPageNumber: Int
        private var pageCount: Int
        private var onCancel: () -> Void
        private var onJump: () -> Void
        private weak var alertController: UIAlertController?
        private weak var jumpAction: UIAlertAction?
        private weak var textField: UITextField?
        private var isPresentingAlert = false

        init(parent: ReaderPageJumpOverlay) {
            self.pageNumberText = parent.$pageNumberText
            self.currentPageNumber = parent.currentPageNumber
            self.pageCount = parent.pageCount
            self.onCancel = parent.onCancel
            self.onJump = parent.onJump
            super.init()
        }

        func update(from parent: ReaderPageJumpOverlay) {
            pageNumberText = parent.$pageNumberText
            currentPageNumber = parent.currentPageNumber
            pageCount = parent.pageCount
            onCancel = parent.onCancel
            onJump = parent.onJump

            if let alertController {
                alertController.message = alertMessage

                if textField?.text != pageNumberText.wrappedValue {
                    textField?.text = pageNumberText.wrappedValue
                }

                jumpAction?.isEnabled = isValidPageNumber(pageNumberText.wrappedValue)
            }
        }

        func presentIfNeeded(from controller: UIViewController) {
            guard alertController == nil, !isPresentingAlert else {
                return
            }

            guard controller.viewIfLoaded?.window != nil else {
                DispatchQueue.main.async { [weak self, weak controller] in
                    guard let self, let controller else {
                        return
                    }

                    self.presentIfNeeded(from: controller)
                }
                return
            }

            let alertController = buildAlertController()
            isPresentingAlert = true
            controller.present(alertController, animated: true) { [weak self] in
                self?.isPresentingAlert = false
                self?.textField?.becomeFirstResponder()
            }
            self.alertController = alertController
        }

        func dismissIfNeeded(animated: Bool) {
            guard let alertController else {
                cleanup()
                return
            }

            alertController.dismiss(animated: animated) { [weak self] in
                self?.cleanup()
            }
        }

        @objc
        private func handleTextDidChange(_ sender: UITextField) {
            let updatedText = sender.text ?? ""
            pageNumberText.wrappedValue = updatedText
            jumpAction?.isEnabled = isValidPageNumber(updatedText)
        }

        @objc
        private func dismissKeyboard() {
            textField?.resignFirstResponder()
        }

        private func buildAlertController() -> UIAlertController {
            let alertController = UIAlertController(
                title: "Go to Page",
                message: alertMessage,
                preferredStyle: .alert
            )

            alertController.addTextField { [weak self] textField in
                guard let self else {
                    return
                }

                textField.placeholder = "Page number"
                textField.keyboardType = .numberPad
                textField.clearButtonMode = .whileEditing
                textField.text = pageNumberText.wrappedValue
                textField.inputAccessoryView = accessoryToolbar()
                textField.addTarget(self, action: #selector(handleTextDidChange(_:)), for: .editingChanged)
                self.textField = textField
            }

            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.cleanup()
                self?.onCancel()
            }
            let jumpAction = UIAlertAction(title: "Jump", style: .default) { [weak self] _ in
                guard let self else {
                    return
                }

                pageNumberText.wrappedValue = textField?.text ?? pageNumberText.wrappedValue
                cleanup()
                onJump()
            }
            jumpAction.isEnabled = isValidPageNumber(pageNumberText.wrappedValue)

            alertController.addAction(cancelAction)
            alertController.addAction(jumpAction)
            self.jumpAction = jumpAction
            return alertController
        }

        private func accessoryToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(
                    barButtonSystemItem: .flexibleSpace,
                    target: nil,
                    action: nil
                ),
                UIBarButtonItem(
                    title: "Done",
                    style: .done,
                    target: self,
                    action: #selector(dismissKeyboard)
                )
            ]
            return toolbar
        }

        private var alertMessage: String {
            "Current page: \(currentPageNumber)\nValid range: 1-\(pageCount)"
        }

        private func isValidPageNumber(_ value: String) -> Bool {
            guard let pageNumber = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }

            return (1...pageCount).contains(pageNumber)
        }

        private func cleanup() {
            alertController = nil
            jumpAction = nil
            textField = nil
            isPresentingAlert = false
        }
    }
}

final class ReaderPageJumpHostViewController: UIViewController {
    var onDidAppear: (() -> Void)?

    override func loadView() {
        view = UIView(frame: .zero)
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }
}
