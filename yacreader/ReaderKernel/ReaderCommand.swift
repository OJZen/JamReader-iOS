import Foundation

enum ReaderCommand: Equatable {
    case advancePage
    case retreatPage
    case goToPage(Int)
    case toggleChrome
    case setChromeVisible(Bool)
    case setLayout(ReaderDisplayLayout)
    case setPageJumpPresented(Bool)
}
