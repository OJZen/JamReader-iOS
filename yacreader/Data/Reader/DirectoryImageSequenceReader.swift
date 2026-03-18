import Foundation

enum DirectoryImageSequenceError: LocalizedError {
    case unreadableDirectory
    case noRenderablePages
    case pageIndexOutOfBounds(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableDirectory:
            return "The image folder could not be opened."
        case .noRenderablePages:
            return "No supported image pages were found in this folder."
        case .pageIndexOutOfBounds(let index):
            return "The requested folder page \(index + 1) does not exist."
        }
    }
}

final class DirectoryImageSequenceReader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadDocument(at directoryURL: URL) throws -> ImageSequenceComicDocument {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isHiddenKey,
                    .nameKey
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw DirectoryImageSequenceError.unreadableDirectory
        }

        let pageFiles = contents
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true && ComicPageNameSorter.isSupportedImagePath(url.lastPathComponent)
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        guard !pageFiles.isEmpty else {
            throw DirectoryImageSequenceError.noRenderablePages
        }

        return ImageSequenceComicDocument(
            url: directoryURL,
            pageNames: pageFiles.map(\.lastPathComponent),
            pageSource: DirectoryImagePageSource(pageFiles: pageFiles)
        )
    }
}

private actor DirectoryImagePageSource: ComicPageDataSource {
    private let pageFiles: [URL]
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 12
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    init(pageFiles: [URL]) {
        self.pageFiles = pageFiles
        self.cacheNamespace = ReaderPageCache.namespace(for: pageFiles.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/"))
    }

    func dataForPage(at index: Int) async throws -> Data {
        guard pageFiles.indices.contains(index) else {
            throw DirectoryImageSequenceError.pageIndexOutOfBounds(index)
        }

        if let cached = cache.object(forKey: NSNumber(value: index)) {
            return Data(referencing: cached)
        }

        let cacheKey = ReaderPageCacheKey(
            namespace: cacheNamespace,
            pageIdentifier: pageFiles[index].lastPathComponent
        )
        if let cachedPage = await sharedCache.data(for: cacheKey) {
            cache.setObject(cachedPage as NSData, forKey: NSNumber(value: index), cost: cachedPage.count)
            return cachedPage
        }

        let data: Data
        do {
            data = try Data(contentsOf: pageFiles[index], options: [.mappedIfSafe])
        } catch {
            throw DirectoryImageSequenceError.unreadableDirectory
        }

        cache.setObject(data as NSData, forKey: NSNumber(value: index), cost: data.count)
        await sharedCache.store(data, for: cacheKey)
        return data
    }

    func prefetchPages(at indices: [Int]) async {
        for index in indices {
            guard pageFiles.indices.contains(index) else {
                continue
            }

            _ = try? await dataForPage(at: index)
        }
    }
}
