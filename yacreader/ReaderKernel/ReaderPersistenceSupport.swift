import Foundation

struct ReaderProgressPersistenceSnapshot: Equatable {
    let pageIndex: Int
    let bookmarkPageIndices: [Int]
}

enum ReaderBookmarkNormalizer {
    static func normalized(
        _ pageIndices: [Int],
        pageCount: Int? = nil,
        maximumCount: Int? = nil
    ) -> [Int] {
        let filtered = pageIndices.filter { pageIndex in
            guard pageIndex >= 0 else {
                return false
            }

            if let pageCount {
                return pageIndex < pageCount
            }

            return true
        }

        let normalized = Array(Set(filtered)).sorted()
        guard let maximumCount, maximumCount > 0 else {
            return normalized
        }

        return Array(normalized.prefix(maximumCount))
    }
}

enum ReaderProgressFactory {
    static func snapshot(
        pageIndex: Int,
        pageCount: Int,
        bookmarkPageIndices: [Int] = [],
        maximumBookmarkCount: Int? = nil
    ) -> ReaderProgressPersistenceSnapshot {
        ReaderProgressPersistenceSnapshot(
            pageIndex: clampedPageIndex(pageIndex, pageCount: pageCount),
            bookmarkPageIndices: ReaderBookmarkNormalizer.normalized(
                bookmarkPageIndices,
                pageCount: pageCount,
                maximumCount: maximumBookmarkCount
            )
        )
    }

    static func clampedPageIndex(_ pageIndex: Int, pageCount: Int) -> Int {
        min(max(pageIndex, 0), max(pageCount - 1, 0))
    }

    static func progress(
        forPageIndex pageIndex: Int,
        pageCount: Int,
        lastOpenedAt: Date = Date()
    ) -> ComicReadingProgress {
        let clampedPageIndex = clampedPageIndex(pageIndex, pageCount: pageCount)
        let currentPage = max(1, clampedPageIndex + 1)
        return ComicReadingProgress(
            currentPage: currentPage,
            pageCount: pageCount,
            hasBeenOpened: true,
            read: currentPage >= pageCount,
            lastTimeOpened: lastOpenedAt
        )
    }
}
