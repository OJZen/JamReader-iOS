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
        case .toggleChrome:
            state.isChromeVisible.toggle()
        case .setChromeVisible(let isVisible):
            state.isChromeVisible = isVisible
        case .setLayout(let layout):
            state.layout = layout
        case .setPageJumpPresented(let isPresented):
            state.isPageJumpPresented = isPresented
        }
    }

    func syncVisiblePageIndex(_ pageIndex: Int) {
        state.currentPageIndex = clampedPageIndex(pageIndex, pageCount: state.descriptor.pageCount)
    }

    func updateDescriptor(
        _ descriptor: ReaderContentDescriptor,
        preferredPageIndex: Int? = nil
    ) {
        state.descriptor = descriptor
        state.layout = descriptor.layout
        state.currentPageIndex = clampedPageIndex(
            preferredPageIndex ?? state.currentPageIndex,
            pageCount: descriptor.pageCount
        )
    }

    func updateCurrentPage(_ pageIndex: Int) {
        state.currentPageIndex = clampedPageIndex(pageIndex, pageCount: state.descriptor.pageCount)
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
        state.isChromeVisible.toggle()
    }

    func setChromeVisible(_ isVisible: Bool) {
        state.isChromeVisible = isVisible
    }

    func hideChrome() {
        state.isChromeVisible = false
    }

    func presentPageJump(defaultPageNumber: Int) {
        state.pendingPageNumberText = "\(max(defaultPageNumber, 1))"
        state.isPageJumpPresented = true
    }

    func dismissPageJump() {
        state.isPageJumpPresented = false
    }

    func updatePendingPageNumberText(_ text: String) {
        state.pendingPageNumberText = text
    }

    private func clampedPageIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        let lastPageIndex = max(pageCount - 1, 0)
        return min(max(pageIndex, 0), lastPageIndex)
    }

    private func resolvedContentKind(for layout: ReaderDisplayLayout) -> ReaderContentKind {
        switch state.descriptor.kind {
        case .pdf:
            return .pdf
        case .imagePaged, .imageContinuous:
            return layout.pagingMode == .verticalContinuous ? .imageContinuous : .imagePaged
        }
    }
}
