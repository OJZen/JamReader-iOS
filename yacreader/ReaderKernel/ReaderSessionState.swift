import Foundation

struct ReaderSessionState: Equatable {
    var descriptor: ReaderContentDescriptor
    var currentPageIndex: Int
    var isChromeVisible: Bool
    var isPageJumpPresented: Bool
    var pendingPageNumberText: String
    var layout: ReaderDisplayLayout

    init(
        descriptor: ReaderContentDescriptor,
        currentPageIndex: Int? = nil,
        isChromeVisible: Bool = false,
        isPageJumpPresented: Bool = false,
        pendingPageNumberText: String = "",
        layout: ReaderDisplayLayout? = nil
    ) {
        self.descriptor = descriptor
        self.currentPageIndex = currentPageIndex ?? descriptor.initialPageIndex
        self.isChromeVisible = isChromeVisible
        self.isPageJumpPresented = isPageJumpPresented
        self.pendingPageNumberText = pendingPageNumberText
        self.layout = layout ?? descriptor.layout
    }
}
