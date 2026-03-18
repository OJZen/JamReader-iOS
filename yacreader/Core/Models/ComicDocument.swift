import Foundation
import PDFKit

enum ComicDocument {
    case pdf(PDFComicDocument)
    case imageSequence(ImageSequenceComicDocument)
    case unsupported(UnsupportedComicDocument)

    var pageCount: Int? {
        switch self {
        case .pdf(let document):
            return document.pageCount
        case .imageSequence(let document):
            return document.pageCount
        case .unsupported:
            return nil
        }
    }

    var fileURL: URL {
        switch self {
        case .pdf(let document):
            return document.url
        case .imageSequence(let document):
            return document.url
        case .unsupported(let document):
            return document.url
        }
    }
}

struct PDFComicDocument {
    let url: URL
    let pdfDocument: PDFDocument

    var pageCount: Int {
        pdfDocument.pageCount
    }
}

protocol ComicPageDataSource: Sendable {
    func dataForPage(at index: Int) async throws -> Data
    func prefetchPages(at indices: [Int]) async
}

extension ComicPageDataSource {
    func prefetchPages(at indices: [Int]) async {
        _ = indices
    }
}

struct ImageSequenceComicDocument {
    let url: URL
    let pageNames: [String]
    let pageSource: any ComicPageDataSource

    var pageCount: Int {
        pageNames.count
    }

    func pageName(at index: Int) -> String? {
        guard pageNames.indices.contains(index) else {
            return nil
        }

        return pageNames[index]
    }
}

struct UnsupportedComicDocument {
    let url: URL
    let fileExtension: String
    let reason: String
}
