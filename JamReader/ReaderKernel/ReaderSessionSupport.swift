import Foundation

enum ReaderPageIndicatorFormatter {
    static func text(
        for document: ComicDocument?,
        currentPageIndex: Int,
        layout: ReaderDisplayLayout
    ) -> String? {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return nil
        }

        guard let document, case .imageSequence = document else {
            return "\(min(currentPageIndex + 1, pageCount)) / \(pageCount)"
        }

        let spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: pageCount, layout: layout)
        guard let spreadIndex = ReaderSpreadDescriptor.spreadIndex(containing: currentPageIndex, in: spreads),
              spreads.indices.contains(spreadIndex)
        else {
            return "\(min(currentPageIndex + 1, pageCount)) / \(pageCount)"
        }

        let visiblePages = spreads[spreadIndex].pageIndices.map { $0 + 1 }
        if visiblePages.count == 2, let firstPage = visiblePages.first, let lastPage = visiblePages.last {
            return "\(firstPage)-\(lastPage) / \(pageCount)"
        }

        return "\(visiblePages.first ?? min(currentPageIndex + 1, pageCount)) / \(pageCount)"
    }
}

enum ReaderPageJumpResolver {
    static func pageIndex(from text: String, pageCount: Int) -> Int? {
        let trimmedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmedValue), (1...pageCount).contains(pageNumber) else {
            return nil
        }

        return pageNumber - 1
    }

    static func validationMessage(pageCount: Int) -> String {
        "Enter a page between 1 and \(pageCount)."
    }
}

extension ReaderSessionController {
    func synchronize(
        document: ComicDocument?,
        fallbackDocumentURL: URL,
        fallbackPageCount: Int,
        currentPageIndex: Int,
        layout: ReaderDisplayLayout
    ) {
        if let document {
            updateDescriptor(
                .resolved(
                    document: document,
                    currentPageIndex: currentPageIndex,
                    layout: layout
                ),
                preferredPageIndex: currentPageIndex
            )
        } else {
            updateDescriptor(
                .placeholder(
                    documentURL: fallbackDocumentURL,
                    pageCount: max(fallbackPageCount, 1),
                    initialPageIndex: currentPageIndex,
                    layout: layout
                ),
                preferredPageIndex: currentPageIndex
            )
        }
    }
}
