import CryptoKit
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

struct DirectoryImageSequenceInspection {
    let directoryURL: URL
    let pageFiles: [URL]
    let regularFiles: [URL]
    let comicInfoURL: URL?
}

nonisolated final class DirectoryImageSequenceInspector {
    private static let auxiliaryFileNames: Set<String> = [
        "comicinfo.xml",
        "thumbs.db",
        "desktop.ini"
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func inspectComicDirectory(at directoryURL: URL) throws -> DirectoryImageSequenceInspection? {
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            return nil
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .nameKey],
            options: [.skipsHiddenFiles]
        )

        var regularFiles: [URL] = []

        for itemURL in contents {
            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                return nil
            }

            if values.isRegularFile == true {
                regularFiles.append(itemURL)
            }
        }

        let pageFiles = sortedPageFiles(in: regularFiles)
        guard !pageFiles.isEmpty else {
            return nil
        }

        let relevantRegularFiles = regularFiles.filter { fileURL in
            !Self.auxiliaryFileNames.contains(fileURL.lastPathComponent.lowercased())
        }
        guard !relevantRegularFiles.isEmpty else {
            return nil
        }

        let imageDominance = Double(pageFiles.count) / Double(relevantRegularFiles.count)
        guard imageDominance >= 0.8 else {
            return nil
        }

        let comicInfoURL = regularFiles.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
        })

        return DirectoryImageSequenceInspection(
            directoryURL: directoryURL,
            pageFiles: pageFiles,
            regularFiles: regularFiles,
            comicInfoURL: comicInfoURL
        )
    }

    func fingerprint(for inspection: DirectoryImageSequenceInspection) throws -> String {
        var digest = Insecure.SHA1()
        var totalSize: Int64 = 0

        let sortedRegularFiles = inspection.regularFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for fileURL in sortedRegularFiles {
            let fileSize = Int64((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            totalSize += fileSize
            digest.update(data: Data("\(fileURL.lastPathComponent.lowercased()):\(fileSize)\n".utf8))
        }

        if let firstPageURL = inspection.pageFiles.first {
            digest.update(data: try fingerprintSample(from: firstPageURL))
        }

        if let lastPageURL = inspection.pageFiles.last, lastPageURL != inspection.pageFiles.first {
            digest.update(data: try fingerprintSample(from: lastPageURL))
        }

        let digestString = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(digestString)-\(inspection.pageFiles.count)-\(totalSize)"
    }

    private func sortedPageFiles(in regularFiles: [URL]) -> [URL] {
        let supportedFiles = regularFiles.filter { url in
            ComicPageNameSorter.isSupportedImagePath(url.lastPathComponent)
        }
        let sortedPageNames = ComicPageNameSorter.sortedPageNames(supportedFiles.map(\.lastPathComponent))
        let filesByName = Dictionary(uniqueKeysWithValues: supportedFiles.map { ($0.lastPathComponent, $0) })
        return sortedPageNames.compactMap { filesByName[$0] }
    }

    private func fingerprintSample(from fileURL: URL, maxBytes: Int = 64 * 1024) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        return try handle.read(upToCount: maxBytes) ?? Data()
    }
}

nonisolated final class DirectoryImageSequenceReader {
    private let fileManager: FileManager
    private let inspector: DirectoryImageSequenceInspector

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.inspector = DirectoryImageSequenceInspector(fileManager: fileManager)
    }

    func loadDocument(at directoryURL: URL) throws -> ImageSequenceComicDocument {
        let inspection: DirectoryImageSequenceInspection
        do {
            guard let resolvedInspection = try inspector.inspectComicDirectory(at: directoryURL) else {
                throw DirectoryImageSequenceError.noRenderablePages
            }
            inspection = resolvedInspection
        } catch let error as DirectoryImageSequenceError {
            throw error
        } catch {
            throw DirectoryImageSequenceError.unreadableDirectory
        }

        guard !inspection.pageFiles.isEmpty else {
            throw DirectoryImageSequenceError.noRenderablePages
        }

        return ImageSequenceComicDocument(
            url: directoryURL,
            pageNames: inspection.pageFiles.map(\.lastPathComponent),
            pageSource: DirectoryImagePageSource(pageFiles: inspection.pageFiles)
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
        cache.totalCostLimit = 48 * 1_024 * 1_024
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
