import Combine
import CryptoKit
import SwiftUI
import UIKit

struct RemoteThumbnailCacheSummary: Hashable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = RemoteThumbnailCacheSummary(fileCount: 0, totalBytes: 0)

    var isEmpty: Bool {
        fileCount == 0 || totalBytes <= 0
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var summaryText: String {
        if fileCount == 1 {
            return "1 cached thumbnail · \(sizeText)"
        }

        return "\(fileCount) cached thumbnails · \(sizeText)"
    }
}

struct RemoteComicThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let profile: RemoteServerProfile
    let item: RemoteDirectoryItem
    let browsingService: RemoteServerBrowsingService
    let placeholderSystemName: String
    let width: CGFloat
    let height: CGFloat

    @StateObject private var loader = RemoteComicThumbnailLoader()

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        placeholderSystemName: String = "doc.richtext",
        width: CGFloat = 74,
        height: CGFloat = 104
    ) {
        self.profile = profile
        self.item = item
        self.browsingService = browsingService
        self.placeholderSystemName = placeholderSystemName
        self.width = width
        self.height = height
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSystemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .task(id: loaderRequestID) {
            loader.load(
                profile: profile,
                item: item,
                browsingService: browsingService,
                targetSize: CGSize(width: width, height: height),
                scale: displayScale
            )
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var loaderRequestID: String {
        "\(item.id)#\(Int(width))x\(Int(height))@\(Int(displayScale * 100))"
    }
}

@MainActor
private final class RemoteComicThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var loadTask: Task<Void, Never>?
    private var requestID: String?

    func load(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        targetSize: CGSize,
        scale: CGFloat
    ) {
        loadTask?.cancel()

        guard item.canOpenAsComic else {
            requestID = nil
            image = nil
            return
        }

        let maxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let requestID = "\(item.id)#\(maxPixelSize)"

        if self.requestID != requestID {
            image = nil
        }

        self.requestID = requestID
        loadTask = Task { [weak self] in
            let image = await RemoteComicThumbnailPipeline.shared.image(
                for: profile,
                item: item,
                browsingService: browsingService,
                maxPixelSize: maxPixelSize
            )

            guard let self, !Task.isCancelled, self.requestID == requestID else {
                return
            }

            self.image = image
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    deinit {
        loadTask?.cancel()
    }
}

@MainActor
final class RemoteComicThumbnailPipeline {
    static let shared = RemoteComicThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    private let fileManager: FileManager
    private let thumbnailCacheRootURL: URL
    private let maximumCachedThumbnailCount = 600
    private let maximumTotalCacheBytes: Int64 = 256 * 1_024 * 1_024

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.thumbnailCacheRootURL = (
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("RemoteThumbnails", isDirectory: true)
        cache.countLimit = 256
        cache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(
        for profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        maxPixelSize: Int
    ) async -> UIImage? {
        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item)
        else {
            return nil
        }

        let cacheKey = Self.cacheKey(for: reference, maxPixelSize: maxPixelSize)
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            return cachedImage
        }

        let diskURL = cachedThumbnailURL(forCacheKey: cacheKey)
        if let diskCachedImage = Self.loadCachedImage(at: diskURL) {
            cache.setObject(
                diskCachedImage,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: diskCachedImage)
            )
            touchCachedThumbnail(at: diskURL)
            return diskCachedImage
        }

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let task = Task<UIImage?, Never> {
            do {
                if let remoteImage = await browsingService.fetchDirectThumbnail(
                    for: profile,
                    reference: reference,
                    maxPixelSize: maxPixelSize
                ) {
                    try? self.storeCachedThumbnail(remoteImage, at: diskURL)
                    try? self.trimCacheIfNeeded()
                    return remoteImage
                }

                let downloadResult = try await browsingService.downloadComicFile(
                    for: profile,
                    reference: reference
                )

                if Task.isCancelled {
                    return nil
                }

                guard let image = Self.extractThumbnail(
                    from: downloadResult.localFileURL,
                    maxPixelSize: maxPixelSize
                ) else {
                    return nil
                }

                try? self.storeCachedThumbnail(image, at: diskURL)
                try? self.trimCacheIfNeeded()
                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[cacheKey] = task
        let image = await task.value
        inFlightTasks[cacheKey] = nil

        if let image {
            cache.setObject(
                image,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: image)
            )
        }

        return image
    }

    func cacheSummary() -> RemoteThumbnailCacheSummary {
        guard fileManager.fileExists(atPath: thumbnailCacheRootURL.path) else {
            return .empty
        }

        guard let enumerator = fileManager.enumerator(
            at: thumbnailCacheRootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        var fileCount = 0
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                continue
            }

            fileCount += 1
            totalBytes += Int64(values?.fileSize ?? 0)
        }

        return RemoteThumbnailCacheSummary(fileCount: fileCount, totalBytes: totalBytes)
    }

    func clearCache() throws {
        cache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()

        guard fileManager.fileExists(atPath: thumbnailCacheRootURL.path) else {
            return
        }

        try fileManager.removeItem(at: thumbnailCacheRootURL)
    }

    func preheat(
        for profile: RemoteServerProfile,
        items: [RemoteDirectoryItem],
        browsingService: RemoteServerBrowsingService,
        maxPixelSize: Int,
        limit: Int,
        skipCount: Int = 0,
        concurrency: Int
    ) async {
        let candidates = Array(
            items
                .filter(\.canOpenAsComic)
                .dropFirst(max(0, skipCount))
                .prefix(max(0, limit))
        )
        guard !candidates.isEmpty else {
            return
        }

        let maximumConcurrency = max(1, min(concurrency, candidates.count))
        var nextIndex = 0

        await withTaskGroup(of: Void.self) { group in
            func enqueueNextIfNeeded() {
                guard nextIndex < candidates.count else {
                    return
                }

                let item = candidates[nextIndex]
                nextIndex += 1
                group.addTask { [weak self] in
                    guard let self else {
                        return
                    }

                    _ = await self.image(
                        for: profile,
                        item: item,
                        browsingService: browsingService,
                        maxPixelSize: maxPixelSize
                    )
                }
            }

            for _ in 0..<maximumConcurrency {
                enqueueNextIfNeeded()
            }

            while await group.next() != nil {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }

                enqueueNextIfNeeded()
            }
        }
    }

    private static func cacheKey(
        for reference: RemoteComicFileReference,
        maxPixelSize: Int
    ) -> String {
        let modifiedAt = Int(reference.modifiedAt?.timeIntervalSince1970 ?? 0)
        return "\(reference.id)#\(reference.fileSize ?? 0)#\(modifiedAt)#\(maxPixelSize)"
    }

    private static func extractThumbnail(from fileURL: URL, maxPixelSize: Int) -> UIImage? {
        let extractor = LibraryComicMetadataExtractor()
        guard let metadata = try? extractor.extractMetadata(for: fileURL),
              let coverImage = metadata.coverImage
        else {
            return nil
        }

        return downsampledImage(from: coverImage, maxPixelSize: maxPixelSize)
    }

    private static func downsampledImage(from image: UIImage, maxPixelSize: Int) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let largestDimension = max(pixelWidth, pixelHeight)

        guard largestDimension > CGFloat(maxPixelSize), largestDimension > 0 else {
            return image
        }

        let scaleRatio = CGFloat(maxPixelSize) / largestDimension
        let targetSize = CGSize(
            width: max(1, image.size.width * scaleRatio),
            height: max(1, image.size.height * scaleRatio)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }

    private func cachedThumbnailURL(forCacheKey cacheKey: String) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return thumbnailCacheRootURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func storeCachedThumbnail(_ image: UIImage, at fileURL: URL) throws {
        guard let data = Self.encodedThumbnailData(from: image) else {
            return
        }

        try fileManager.createDirectory(
            at: thumbnailCacheRootURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        touchCachedThumbnail(at: fileURL)
    }

    private func trimCacheIfNeeded() throws {
        guard fileManager.fileExists(atPath: thumbnailCacheRootURL.path) else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: thumbnailCacheRootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var cachedFiles: [CachedThumbnailFileRecord] = []
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else {
                continue
            }

            let size = Int64(values?.fileSize ?? 0)
            totalBytes += size
            cachedFiles.append(
                CachedThumbnailFileRecord(
                    url: fileURL,
                    size: size,
                    lastAccessDate: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        guard cachedFiles.count > maximumCachedThumbnailCount || totalBytes > maximumTotalCacheBytes else {
            return
        }

        let evictionCandidates = cachedFiles.sorted { lhs, rhs in
            lhs.lastAccessDate < rhs.lastAccessDate
        }

        var remainingCount = cachedFiles.count
        var remainingBytes = totalBytes

        for candidate in evictionCandidates {
            guard remainingCount > maximumCachedThumbnailCount
                    || remainingBytes > maximumTotalCacheBytes
            else {
                break
            }

            try fileManager.removeItem(at: candidate.url)
            remainingCount -= 1
            remainingBytes -= candidate.size
        }
    }

    private func touchCachedThumbnail(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private static func loadCachedImage(at fileURL: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path)
        else {
            return nil
        }

        return image
    }

    private static func encodedThumbnailData(from image: UIImage) -> Data? {
        if let jpegData = image.jpegData(compressionQuality: 0.82) {
            return jpegData
        }

        return image.pngData()
    }
}

private struct CachedThumbnailFileRecord {
    let url: URL
    let size: Int64
    let lastAccessDate: Date
}
