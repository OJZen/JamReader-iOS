import Foundation

enum ReaderCommand: Equatable {
    case advancePage
    case retreatPage
    case goToPage(Int)
    case syncVisiblePage(Int)
    case toggleChrome
    case hideChrome
    case setChromeVisible(Bool)
    case setLayout(ReaderDisplayLayout)
    case setPageJumpPresented(Bool)
    case presentPageJump(defaultPageNumber: Int)
    case dismissPageJump
    case updatePendingPageNumberText(String)
}
