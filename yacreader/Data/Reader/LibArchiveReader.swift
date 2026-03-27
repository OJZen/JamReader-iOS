import Foundation

enum LibArchiveError: LocalizedError {
    case noRenderablePages
    case pageIndexOutOfBounds(Int)

    var errorDescription: String? {
        switch self {
        case .noRenderablePages:
            return "No supported image pages were found inside this archive."
        case .pageIndexOutOfBounds(let index):
            return "The requested archive page \(index + 1) does not exist."
        }
    }
}

struct LibArchiveEntry: Sendable {
    let path: String
    let archiveIndex: Int
}

final class LibArchiveReader {
    func loadDocument(at archiveURL: URL) throws -> ImageSequenceComicDocument {
        let archiveReader = try YRLibArchiveReader(archiveURL: archiveURL)
        let orderedEntries = try orderedPageEntries(from: archiveReader.entryPaths)

        return ImageSequenceComicDocument(
            url: archiveURL,
            pageNames: orderedEntries.map(\.path),
            pageSource: LibArchivePageSource(archiveURL: archiveURL, archiveReader: archiveReader, entries: orderedEntries)
        )
    }

    func extractMetadata(at archiveURL: URL, coverPage: Int = 1) throws -> ArchiveImageMetadata {
        let archiveReader = try YRLibArchiveReader(archiveURL: archiveURL)
        let orderedEntries = try orderedPageEntries(from: archiveReader.entryPaths)
        let coverIndex = min(max(coverPage - 1, 0), orderedEntries.count - 1)
        let coverData = try archiveReader.dataForEntry(at: orderedEntries[coverIndex].archiveIndex)
        let embeddedComicInfoData = try preferredEmbeddedComicInfoEntry(
            from: archiveReader.entryPaths
        ).flatMap { entry in
            try archiveReader.dataForEntry(at: entry.archiveIndex)
        }

        return ArchiveImageMetadata(
            pageCount: orderedEntries.count,
            coverData: coverData,
            embeddedComicInfoData: embeddedComicInfoData
        )
    }

    /// Lightweight: count pages without decompressing any data.
    func countPages(at archiveURL: URL) throws -> Int {
        let archiveReader = try YRLibArchiveReader(archiveURL: archiveURL)
        return try orderedPageEntries(from: archiveReader.entryPaths).count
    }

    private func orderedPageEntries(from entryPaths: [String]) throws -> [LibArchiveEntry] {
        let pageEntries = entryPaths.enumerated().compactMap { archiveIndex, path -> LibArchiveEntry? in
            guard ComicPageNameSorter.isSupportedImagePath(path) else {
                return nil
            }

            return LibArchiveEntry(path: path, archiveIndex: archiveIndex)
        }

        guard !pageEntries.isEmpty else {
            throw LibArchiveError.noRenderablePages
        }

        let sortedPaths = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.path))
        var entriesByPath = Dictionary(grouping: pageEntries, by: \.path)
        var orderedEntries: [LibArchiveEntry] = []
        orderedEntries.reserveCapacity(pageEntries.count)

        for path in sortedPaths {
            guard var candidates = entriesByPath[path], let entry = candidates.first else {
                continue
            }

            candidates.removeFirst()
            entriesByPath[path] = candidates
            orderedEntries.append(entry)
        }

        return orderedEntries
    }

    private func preferredEmbeddedComicInfoEntry(from entryPaths: [String]) throws -> LibArchiveEntry? {
        guard let preferredPath = EmbeddedComicInfoLocator.preferredPath(in: entryPaths) else {
            return nil
        }

        return entryPaths.enumerated().first { _, path in
            path == preferredPath
        }.map { archiveIndex, path in
            LibArchiveEntry(path: path, archiveIndex: archiveIndex)
        }
    }
}

private actor LibArchivePageSource: ComicPageDataSource {
    private let archiveReader: YRLibArchiveReader
    private let entries: [LibArchiveEntry]
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    init(archiveURL: URL, archiveReader: YRLibArchiveReader, entries: [LibArchiveEntry]) {
        self.archiveReader = archiveReader
        self.entries = entries
        self.cacheNamespace = ReaderPageCache.namespace(for: archiveURL)
    }

    func dataForPage(at index: Int) async throws -> Data {
        guard entries.indices.contains(index) else {
            throw LibArchiveError.pageIndexOutOfBounds(index)
        }

        if let cachedData = cache.object(forKey: NSNumber(value: index)) {
            return Data(referencing: cachedData)
        }

        let cacheKey = ReaderPageCacheKey(
            namespace: cacheNamespace,
            pageIdentifier: entries[index].path
        )
        if let cachedPage = await sharedCache.data(for: cacheKey) {
            cache.setObject(cachedPage as NSData, forKey: NSNumber(value: index), cost: cachedPage.count)
            return cachedPage
        }

        let pageData = try archiveReader.dataForEntry(at: entries[index].archiveIndex)
        cache.setObject(pageData as NSData, forKey: NSNumber(value: index), cost: pageData.count)
        await sharedCache.store(pageData, for: cacheKey)
        return pageData
    }

    func prefetchPages(at indices: [Int]) async {
        for index in indices {
            guard entries.indices.contains(index) else {
                continue
            }

            _ = try? await dataForPage(at: index)
        }
    }
}
