import Foundation

struct LibraryComic: Identifiable, Hashable {
    let id: Int64
    let parentID: Int64
    let fileName: String
    let path: String?
    let hash: String
    let title: String?
    let issueNumber: String?
    let currentPage: Int
    let pageCount: Int?
    let fileSizeBytes: Int64?
    let bookmarkPageIndices: [Int]
    let read: Bool
    let hasBeenOpened: Bool
    let coverSizeRatio: Double?
    let lastOpenedAt: Date?
    let addedAt: Date?
    let type: LibraryFileType
    let series: String?
    let volume: String?
    let rating: Double?
    let isFavorite: Bool

    func updatingFavorite(_ isFavorite: Bool) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: title,
            issueNumber: issueNumber,
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: read,
            hasBeenOpened: hasBeenOpened,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: lastOpenedAt,
            addedAt: addedAt,
            type: type,
            series: series,
            volume: volume,
            rating: rating,
            isFavorite: isFavorite
        )
    }

    func updatingRating(_ rating: Double?) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: title,
            issueNumber: issueNumber,
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: read,
            hasBeenOpened: hasBeenOpened,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: lastOpenedAt,
            addedAt: addedAt,
            type: type,
            series: series,
            volume: volume,
            rating: rating,
            isFavorite: isFavorite
        )
    }

    func updatingReadState(
        _ isRead: Bool,
        resolvedPageCount: Int? = nil,
        lastOpenedAt: Date = Date()
    ) -> LibraryComic {
        let effectivePageCount = resolvedPageCount ?? pageCount
        let resolvedCurrentPage = isRead ? max(effectivePageCount ?? currentPage, 1) : 1

        return LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: title,
            issueNumber: issueNumber,
            currentPage: resolvedCurrentPage,
            pageCount: effectivePageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: isRead,
            hasBeenOpened: isRead,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: isRead ? lastOpenedAt : nil,
            addedAt: addedAt,
            type: type,
            series: series,
            volume: volume,
            rating: rating,
            isFavorite: isFavorite
        )
    }

    func updatingBookmarkPageIndices(_ bookmarkPageIndices: [Int]) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: title,
            issueNumber: issueNumber,
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: read,
            hasBeenOpened: hasBeenOpened,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: lastOpenedAt,
            addedAt: addedAt,
            type: type,
            series: series,
            volume: volume,
            rating: rating,
            isFavorite: isFavorite
        )
    }

    func updatingReadingProgress(_ progress: ComicReadingProgress) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: title,
            issueNumber: issueNumber,
            currentPage: progress.currentPage,
            pageCount: progress.pageCount ?? pageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: progress.read,
            hasBeenOpened: progress.hasBeenOpened,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: progress.lastTimeOpened,
            addedAt: addedAt,
            type: type,
            series: series,
            volume: volume,
            rating: rating,
            isFavorite: isFavorite
        )
    }

    func applying(metadata: LibraryComicMetadata) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: parentID,
            fileName: fileName,
            path: path,
            hash: hash,
            title: normalized(metadata.title),
            issueNumber: normalized(metadata.issueNumber),
            currentPage: currentPage,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            bookmarkPageIndices: bookmarkPageIndices,
            read: read,
            hasBeenOpened: hasBeenOpened,
            coverSizeRatio: coverSizeRatio,
            lastOpenedAt: lastOpenedAt,
            addedAt: addedAt,
            type: metadata.type,
            series: normalized(metadata.series),
            volume: normalized(metadata.volume),
            rating: rating,
            isFavorite: isFavorite
        )
    }

    var displayTitle: String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? fileName : trimmedTitle
    }

    var issueLabel: String? {
        let trimmed = issueNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var subtitle: String {
        let pieces = [series, volume]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }

        if pieces.isEmpty {
            return fileName
        }

        return pieces.joined(separator: " · ")
    }

    var progressText: String {
        if read {
            return "Read"
        }

        if hasBeenOpened, currentPage > 0 {
            if let pageCount, pageCount > 0 {
                return "Page \(currentPage) / \(pageCount)"
            }

            return "Page \(currentPage)"
        }

        if let pageCount, pageCount > 0 {
            return "\(pageCount) pages"
        }

        return "Unread"
    }

    var fileSizeText: String? {
        guard let fileSizeBytes, fileSizeBytes > 0 else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var isContinueReadingCandidate: Bool {
        hasBeenOpened && !read
    }

    func belongs(
        to specialCollection: LibrarySpecialCollectionKind,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays,
        now: Date = Date()
    ) -> Bool {
        switch specialCollection {
        case .reading:
            return isContinueReadingCandidate
        case .favorites:
            return isFavorite
        case .recent:
            guard let addedAt else {
                return false
            }

            let cutoff = now.addingTimeInterval(TimeInterval(-max(1, recentDays) * 86_400))
            return addedAt > cutoff
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
