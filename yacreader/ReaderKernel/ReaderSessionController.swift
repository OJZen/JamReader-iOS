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
        let lastPageIndex = max(state.descriptor.pageCount - 1, 0)
        state.currentPageIndex = min(max(pageIndex, 0), lastPageIndex)
    }
}
