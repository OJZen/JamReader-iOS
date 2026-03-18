import PDFKit
import SwiftUI

struct PDFReaderContainerView: UIViewRepresentable {
    let document: PDFDocument
    let requestedPageIndex: Int
    let rotation: ReaderRotationAngle
    let onPageChanged: (Int) -> Void
    let onReaderChromeToggle: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rotation: rotation,
            onPageChanged: onPageChanged,
            onReaderChromeToggle: onReaderChromeToggle
        )
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
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

        context.coordinator.pdfView = pdfView
        context.coordinator.onReaderChromeToggle = onReaderChromeToggle
        syncRequestedPage(in: pdfView, coordinator: context.coordinator)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        context.coordinator.onReaderChromeToggle = onReaderChromeToggle

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
        var onReaderChromeToggle: () -> Void

        init(
            rotation: ReaderRotationAngle,
            onPageChanged: @escaping (Int) -> Void,
            onReaderChromeToggle: @escaping () -> Void
        ) {
            self.lastAppliedRotation = rotation
            self.onPageChanged = onPageChanged
            self.onReaderChromeToggle = onReaderChromeToggle
            self.pageTurnFeedbackGenerator.prepare()
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
            lastReportedPageIndex = pageIndex
            onPageChanged(pageIndex)
        }

        @objc
        func handleSingleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let pdfView = pdfView else {
                return
            }

            if pdfView.scaleFactor > pdfView.scaleFactorForSizeToFit + 0.01 {
                onReaderChromeToggle()
                return
            }

            let tapLocation = gestureRecognizer.location(in: pdfView)
            let viewWidth = max(pdfView.bounds.width, 1)
            let horizontalRatio = tapLocation.x / viewWidth
            let edgeRatio: CGFloat = pdfView.traitCollection.horizontalSizeClass == .regular ? 0.18 : 0.24

            if horizontalRatio < edgeRatio {
                if goToPreviousPage() {
                    pageTurnFeedbackGenerator.impactOccurred()
                    pageTurnFeedbackGenerator.prepare()
                    return
                }
            } else if horizontalRatio > 1 - edgeRatio {
                if goToNextPage() {
                    pageTurnFeedbackGenerator.impactOccurred()
                    pageTurnFeedbackGenerator.prepare()
                    return
                }
            }

            onReaderChromeToggle()
        }

        private func goToPreviousPage() -> Bool {
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
            lastReportedPageIndex = targetIndex
            onPageChanged(targetIndex)
            return true
        }

        private func goToNextPage() -> Bool {
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
            lastReportedPageIndex = targetIndex
            onPageChanged(targetIndex)
            return true
        }
    }
}
