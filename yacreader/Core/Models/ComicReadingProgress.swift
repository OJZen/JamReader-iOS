import Foundation

struct ComicReadingProgress: Equatable {
    let currentPage: Int
    let pageCount: Int?
    let hasBeenOpened: Bool
    let read: Bool
    let lastTimeOpened: Date
}
