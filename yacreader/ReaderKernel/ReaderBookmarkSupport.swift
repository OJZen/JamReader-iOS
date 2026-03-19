import Foundation

struct ReaderBookmarkItem: Identifiable, Hashable {
    let pageIndex: Int
    let pageNumber: Int

    var id: Int {
        pageIndex
    }
}

enum ReaderBookmarkSupport {
    static func toggled(
        _ pageIndices: [Int],
        at pageIndex: Int,
        pageCount: Int? = nil,
        maximumCount: Int? = nil
    ) -> [Int] {
        var updatedPageIndices = pageIndices

        if let existingIndex = updatedPageIndices.firstIndex(of: pageIndex) {
            updatedPageIndices.remove(at: existingIndex)
        } else {
            updatedPageIndices.append(pageIndex)
        }

        return ReaderBookmarkNormalizer.normalized(
            updatedPageIndices,
            pageCount: pageCount,
            maximumCount: maximumCount
        )
    }

    static func items(from pageIndices: [Int]) -> [ReaderBookmarkItem] {
        pageIndices.map { pageIndex in
            ReaderBookmarkItem(pageIndex: pageIndex, pageNumber: pageIndex + 1)
        }
    }
}
