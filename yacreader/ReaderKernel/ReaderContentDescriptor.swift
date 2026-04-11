import Foundation

enum ReaderContentKind: Equatable {
    case pdf
    case ebook
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

extension ReaderContentDescriptor {
    static func placeholder(
        documentURL: URL,
        pageCount: Int = 1,
        initialPageIndex: Int = 0,
        layout: ReaderDisplayLayout
    ) -> ReaderContentDescriptor {
        ReaderContentDescriptor(
            documentURL: documentURL,
            kind: layout.pagingMode == .verticalContinuous ? .imageContinuous : .imagePaged,
            pageCount: max(pageCount, 1),
            initialPageIndex: max(initialPageIndex, 0),
            layout: layout
        )
    }

    static func resolved(
        document: ComicDocument,
        currentPageIndex: Int,
        layout: ReaderDisplayLayout
    ) -> ReaderContentDescriptor {
        ReaderContentDescriptor(
            documentURL: document.fileURL,
            kind: contentKind(for: document, layout: layout),
            pageCount: max(document.pageCount ?? 1, 1),
            initialPageIndex: max(currentPageIndex, 0),
            layout: layout
        )
    }

    private static func contentKind(
        for document: ComicDocument,
        layout: ReaderDisplayLayout
    ) -> ReaderContentKind {
        switch document {
        case .pdf:
            return .pdf
        case .ebook:
            return .ebook
        case .imageSequence:
            return layout.pagingMode == .verticalContinuous ? .imageContinuous : .imagePaged
        case .unsupported:
            return layout.pagingMode == .verticalContinuous ? .imageContinuous : .imagePaged
        }
    }
}
