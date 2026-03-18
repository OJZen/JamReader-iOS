import Foundation

enum ReaderContentKind: Equatable {
    case pdf
    case imagePaged
    case imageContinuous
}

struct ReaderContentDescriptor: Equatable {
    let documentURL: URL
    let kind: ReaderContentKind
    let pageCount: Int
    let initialPageIndex: Int
    let layout: ReaderDisplayLayout
}
