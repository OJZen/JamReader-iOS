import Foundation

enum EBookReaderKind: Equatable, Sendable {
    case quickLook
    case epubJS
}

enum ComicDocument: @unchecked Sendable {
    case imageSequence(ImageSequenceComicDocument)
    case ebook(EBookComicDocument)
    case unsupported(UnsupportedComicDocument)

    var pageCount: Int? {
        switch self {
        case .imageSequence(let document):
            return document.pageCount
        case .ebook:
            return nil
        case .unsupported:
            return nil
        }
    }

    var fileURL: URL {
        switch self {
        case .imageSequence(let document):
            return document.url
        case .ebook(let document):
            return document.url
        case .unsupported(let document):
            return document.url
        }
    }
}

nonisolated enum ImageSequenceDocumentKind: Equatable, Sendable {
    case comicImages
    case renderedDocument
}

struct EBookComicDocument: Sendable {
    let url: URL
    let fileExtension: String
    let readerKind: EBookReaderKind
    let documentID: String
}

nonisolated protocol ComicPageDataSource: AnyObject, Sendable {
    func dataForPage(at index: Int) async throws -> Data
    func prefetchPages(at indices: [Int]) async
    func close() async
}

extension ComicPageDataSource {
    func prefetchPages(at indices: [Int]) async {
        _ = indices
    }

    func close() async {
    }
}

nonisolated struct ImageSequenceComicDocument: Sendable {
    let url: URL
    let pageNames: [String]
    let pageSource: any ComicPageDataSource
    let kind: ImageSequenceDocumentKind

    init(
        url: URL,
        pageNames: [String],
        pageSource: any ComicPageDataSource,
        kind: ImageSequenceDocumentKind = .comicImages
    ) {
        self.url = url
        self.pageNames = pageNames
        self.pageSource = pageSource
        self.kind = kind
    }

    var pageCount: Int {
        pageNames.count
    }

    var usesComicImageLayout: Bool {
        kind == .comicImages
    }

    func pageName(at index: Int) -> String? {
        guard pageNames.indices.contains(index) else {
            return nil
        }

        return pageNames[index]
    }
}

struct UnsupportedComicDocument: Sendable {
    let url: URL
    let fileExtension: String
    let reason: String
}
