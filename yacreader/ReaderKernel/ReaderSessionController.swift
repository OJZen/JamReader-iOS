import Combine
import Foundation

@MainActor
final class ReaderSessionController: ObservableObject {
    @Published private(set) var state: ReaderSessionState

    init(state: ReaderSessionState) {
        self.state = state
    }

    convenience init(descriptor: ReaderContentDescriptor) {
        self.init(state: ReaderSessionState(descriptor: descriptor))
    }

    func apply(_ command: ReaderCommand) {
        switch command {
        case .advancePage:
            let lastPageIndex = max(state.descriptor.pageCount - 1, 0)
            state.currentPageIndex = min(state.currentPageIndex + 1, lastPageIndex)
        case .retreatPage:
            state.currentPageIndex = max(state.currentPageIndex - 1, 0)
        case .goToPage(let pageIndex):
            let lastPageIndex = max(state.descriptor.pageCount - 1, 0)
            state.currentPageIndex = min(max(pageIndex, 0), lastPageIndex)
        case .syncVisiblePage(let pageIndex):
            state.currentPageIndex = clampedPageIndex(pageIndex, pageCount: state.descriptor.pageCount)
        case .toggleChrome:
            state.isChromeVisible.toggle()
        case .hideChrome:
            state.isChromeVisible = false
        case .setChromeVisible(let isVisible):
            state.isChromeVisible = isVisible
        case .setLayout(let layout):
            state.layout = layout
        case .setPageJumpPresented(let isPresented):
            state.isPageJumpPresented = isPresented
        case .presentPageJump(let defaultPageNumber):
            state.pendingPageNumberText = "\(max(defaultPageNumber, 1))"
            state.isPageJumpPresented = true
        case .dismissPageJump:
            state.isPageJumpPresented = false
            state.pendingPageNumberText = ""
        case .updatePendingPageNumberText(let text):
            state.pendingPageNumberText = text
        }
    }

    func syncVisiblePageIndex(_ pageIndex: Int) {
        apply(.syncVisiblePage(pageIndex))
    }

    func updateDescriptor(
        _ descriptor: ReaderContentDescriptor,
        preferredPageIndex: Int? = nil
    ) {
        let currentLayout = state.layout
        state.descriptor = descriptor
        // Preserve user's manual layout changes unless the content kind demands a different layout.
        if currentLayout.pagingMode != descriptor.layout.pagingMode
            || currentLayout.readingDirection != descriptor.layout.readingDirection {
            state.layout = descriptor.layout
        }
        state.currentPageIndex = clampedPageIndex(
            preferredPageIndex ?? state.currentPageIndex,
            pageCount: descriptor.pageCount
        )
    }

    func updateCurrentPage(_ pageIndex: Int) {
        apply(.goToPage(pageIndex))
    }

    func updateLayout(_ layout: ReaderDisplayLayout) {
        state.layout = layout
        state.descriptor = ReaderContentDescriptor(
            documentURL: state.descriptor.documentURL,
            kind: resolvedContentKind(for: layout),
            pageCount: state.descriptor.pageCount,
            initialPageIndex: state.currentPageIndex,
            layout: layout
        )
    }

    func toggleChrome() {
        apply(.toggleChrome)
    }

    func setChromeVisible(_ isVisible: Bool) {
        apply(.setChromeVisible(isVisible))
    }

    func hideChrome() {
        apply(.hideChrome)
    }

    func presentPageJump(defaultPageNumber: Int) {
        apply(.presentPageJump(defaultPageNumber: defaultPageNumber))
    }

    func dismissPageJump() {
        apply(.dismissPageJump)
    }

    func updatePendingPageNumberText(_ text: String) {
        apply(.updatePendingPageNumberText(text))
    }

    private func clampedPageIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        let lastPageIndex = max(pageCount - 1, 0)
        return min(max(pageIndex, 0), lastPageIndex)
    }

    private func resolvedContentKind(for layout: ReaderDisplayLayout) -> ReaderContentKind {
        switch state.descriptor.kind {
        case .pdf:
            return .pdf
        case .ebook:
            return .ebook
        case .imagePaged, .imageContinuous:
            return layout.pagingMode == .verticalContinuous ? .imageContinuous : .imagePaged
        }
    }
}
