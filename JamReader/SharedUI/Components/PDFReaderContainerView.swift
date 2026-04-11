import PDFKit
import SwiftUI

struct PDFReaderContainerView: UIViewRepresentable {
    let document: PDFDocument
    let requestedPageIndex: Int
    let rotation: ReaderRotationAngle
    let onPageChanged: (Int) -> Void
    let onReaderTap: (ReaderTapRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rotation: rotation,
            onPageChanged: onPageChanged,
            onReaderTap: onReaderTap
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = ReaderPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.displaysPageBreaks = false
        pdfView.backgroundColor = .black
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.document = document
        pdfView.isUserInteractionEnabled = true

        let singleTapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTapGestureRecognizer.numberOfTapsRequired = 1
        pdfView.addGestureRecognizer(singleTapGestureRecognizer)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )

        pdfView.onAdvancePage = { [weak coordinator = context.coordinator] in
            coordinator?.goToNextPage()
        }
        pdfView.onRetreatPage = { [weak coordinator = context.coordinator] in
            coordinator?.goToPreviousPage()
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.onReaderTap = onReaderTap
        syncRequestedPage(in: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        context.coordinator.onReaderTap = onReaderTap

        let rotationChanged = context.coordinator.lastAppliedRotation != rotation
        if pdfView.document !== document {
            pdfView.document = document
            context.coordinator.lastReportedPageIndex = nil
        }

        if rotationChanged {
            context.coordinator.lastAppliedRotation = rotation
            pdfView.autoScales = true
        }

        syncRequestedPage(in: pdfView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
    }

    private func syncRequestedPage(in pdfView: PDFView, coordinator: Coordinator) {
        guard document.pageCount > 0 else {
            return
        }

        let clampedPageIndex = min(max(requestedPageIndex, 0), document.pageCount - 1)
        if coordinator.lastReportedPageIndex == clampedPageIndex {
            return
        }

        if let currentPage = pdfView.currentPage,
           document.index(for: currentPage) == clampedPageIndex
        {
            coordinator.lastReportedPageIndex = clampedPageIndex
            return
        }

        guard let page = document.page(at: clampedPageIndex) else {
            return
        }

        pdfView.go(to: page)
        coordinator.lastReportedPageIndex = clampedPageIndex
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var lastReportedPageIndex: Int?
        var lastAppliedRotation: ReaderRotationAngle
        private let pageTurnFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)

        var onPageChanged: (Int) -> Void
        var onReaderTap: (ReaderTapRegion) -> Void

        init(
            rotation: ReaderRotationAngle,
            onPageChanged: @escaping (Int) -> Void,
            onReaderTap: @escaping (ReaderTapRegion) -> Void
        ) {
            self.lastAppliedRotation = rotation
            self.onPageChanged = onPageChanged
            self.onReaderTap = onReaderTap
            self.pageTurnFeedbackGenerator.prepare()
        }

        private func notifyPageChangedIfNeeded(_ pageIndex: Int) {
            guard lastReportedPageIndex != pageIndex else {
                return
            }

            lastReportedPageIndex = pageIndex
            DispatchQueue.main.async { [onPageChanged] in
                onPageChanged(pageIndex)
            }
        }

        @objc
        func pageDidChange(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage
            else {
                return
            }

            let pageIndex = document.index(for: currentPage)
            notifyPageChangedIfNeeded(pageIndex)
        }

        @objc
        func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let pdfView = pdfView else {
                return
            }

            if pdfView.scaleFactor > pdfView.scaleFactorForSizeToFit + 0.01 {
                onReaderTap(.center)
                return
            }

            let tapLocation = gestureRecognizer.location(in: pdfView)
            let viewWidth = max(pdfView.bounds.width, 1)
            let horizontalRatio = tapLocation.x / viewWidth
            let edgeRatio: CGFloat = viewWidth >= AppLayout.regularReaderLayoutMinWidth ? 0.18 : 0.24

            if horizontalRatio < edgeRatio {
                if goToPreviousPage() {
                    pageTurnFeedbackGenerator.impactOccurred()
                    pageTurnFeedbackGenerator.prepare()
                    return
                }
                onReaderTap(.leading)
                return
            } else if horizontalRatio > 1 - edgeRatio {
                if goToNextPage() {
                    pageTurnFeedbackGenerator.impactOccurred()
                    pageTurnFeedbackGenerator.prepare()
                    return
                }
                onReaderTap(.trailing)
                return
            }

            onReaderTap(.center)
        }

        @discardableResult
        func goToPreviousPage() -> Bool {
            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage
            else {
                return false
            }

            let currentIndex = document.index(for: currentPage)
            let targetIndex = currentIndex - 1
            guard targetIndex >= 0, let targetPage = document.page(at: targetIndex) else {
                return false
            }

            pdfView.go(to: targetPage)
            notifyPageChangedIfNeeded(targetIndex)
            return true
        }

        @discardableResult
        func goToNextPage() -> Bool {
            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage
            else {
                return false
            }

            let currentIndex = document.index(for: currentPage)
            let targetIndex = currentIndex + 1
            guard targetIndex < document.pageCount, let targetPage = document.page(at: targetIndex) else {
                return false
            }

            pdfView.go(to: targetPage)
            notifyPageChangedIfNeeded(targetIndex)
            return true
        }
    }
}

private final class ReaderPDFView: PDFView {
    var onAdvancePage: (() -> Void)?
    var onRetreatPage: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            resignFirstResponder()
        } else {
            becomeFirstResponder()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let nextPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputRightArrow,
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        nextPageCommand.discoverabilityTitle = "Next Page"

        let previousPageCommand = UIKeyCommand(
            input: UIKeyCommand.inputLeftArrow,
            modifierFlags: [],
            action: #selector(handleRetreatPage)
        )
        previousPageCommand.discoverabilityTitle = "Previous Page"

        let nextPageDownCommand = UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        nextPageDownCommand.discoverabilityTitle = "Next Page"

        let previousPageUpCommand = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: [],
            action: #selector(handleRetreatPage)
        )
        previousPageUpCommand.discoverabilityTitle = "Previous Page"

        let nextPageSpaceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [],
            action: #selector(handleAdvancePage)
        )
        nextPageSpaceCommand.discoverabilityTitle = "Next Page"

        let previousPageShiftSpaceCommand = UIKeyCommand(
            input: " ",
            modifierFlags: [.shift],
            action: #selector(handleRetreatPage)
        )
        previousPageShiftSpaceCommand.discoverabilityTitle = "Previous Page"

        return [
            nextPageCommand,
            previousPageCommand,
            nextPageDownCommand,
            previousPageUpCommand,
            nextPageSpaceCommand,
            previousPageShiftSpaceCommand
        ]
    }

    @objc
    private func handleAdvancePage() {
        onAdvancePage?()
    }

    @objc
    private func handleRetreatPage() {
        onRetreatPage?()
    }
}
