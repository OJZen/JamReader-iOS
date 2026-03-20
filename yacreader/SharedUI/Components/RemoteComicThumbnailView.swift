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
    private let diskCache: RemoteThumbnailDiskCacheStore

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.thumbnailCacheRootURL = (
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("RemoteThumbnails", isDirectory: true)
        self.diskCache = RemoteThumbnailDiskCacheStore(
            fileManager: fileManager,
            cacheRootURL: thumbnailCacheRootURL,
            maximumCachedThumbnailCount: maximumCachedThumbnailCount,
            maximumTotalCacheBytes: maximumTotalCacheBytes
        )
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
        if let diskCachedImage = diskCache.loadCachedImage(at: diskURL) {
            cache.setObject(
                diskCachedImage,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: diskCachedImage)
            )
            diskCache.touchCachedThumbnail(at: diskURL)
            return diskCachedImage
        }

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let worker = RemoteComicThumbnailWorker(
            diskCache: diskCache
        )
        let task = Task<UIImage?, Never> {
            await worker.buildThumbnail(
                for: profile,
                reference: reference,
                browsingService: browsingService,
                maxPixelSize: maxPixelSize,
                diskURL: diskURL
            )
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
        diskCache.cacheSummary()
    }

    func clearCache() throws {
        cache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
        try diskCache.clearCache()
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
}

private struct CachedThumbnailFileRecord {
    let url: URL
    let size: Int64
    let lastAccessDate: Date
}

private final class RemoteThumbnailDiskCacheStore: @unchecked Sendable {
    nonisolated(unsafe) private let fileManager: FileManager
    private let cacheRootURL: URL
    private let maximumCachedThumbnailCount: Int
    private let maximumTotalCacheBytes: Int64
    private let summaryLock = NSLock()
    private let maintenanceQueue = DispatchQueue(
        label: "YACReader.RemoteThumbnailDiskCacheMaintenance",
        qos: .utility
    )

    nonisolated(unsafe) private var cachedSummary: RemoteThumbnailCacheSummary?
    nonisolated(unsafe) private var trimScheduled = false

    init(
        fileManager: FileManager,
        cacheRootURL: URL,
        maximumCachedThumbnailCount: Int,
        maximumTotalCacheBytes: Int64
    ) {
        self.fileManager = fileManager
        self.cacheRootURL = cacheRootURL
        self.maximumCachedThumbnailCount = maximumCachedThumbnailCount
        self.maximumTotalCacheBytes = maximumTotalCacheBytes
    }

    nonisolated func cacheSummary() -> RemoteThumbnailCacheSummary {
        if let cachedSummary = withSummaryLock({ cachedSummary }) {
            return cachedSummary
        }

        let scannedSummary = scanSummaryFromDisk()

        return withSummaryLock {
            if let cachedSummary {
                return cachedSummary
            }

            cachedSummary = scannedSummary
            return scannedSummary
        }
    }

    nonisolated func clearCache() throws {
        if fileManager.fileExists(atPath: cacheRootURL.path) {
            try fileManager.removeItem(at: cacheRootURL)
        }

        withSummaryLock {
            cachedSummary = RemoteThumbnailCacheSummary(fileCount: 0, totalBytes: 0)
            trimScheduled = false
        }
    }

    nonisolated func loadCachedImage(at fileURL: URL) -> UIImage? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let image = UIImage(contentsOfFile: fileURL.path)
        else {
            return nil
        }

        return image
    }

    nonisolated func storeEncodedThumbnailData(_ data: Data, at fileURL: URL) throws {
        let previousSize = cachedFileSize(at: fileURL)

        try fileManager.createDirectory(
            at: cacheRootURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        touchCachedThumbnail(at: fileURL)

        updateSummaryAfterStore(
            previousSize: previousSize,
            newSize: Int64(data.count)
        )
    }

    nonisolated func touchCachedThumbnail(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    nonisolated private func cachedFileSize(at fileURL: URL) -> Int64? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    nonisolated private func updateSummaryAfterStore(previousSize: Int64?, newSize: Int64) {
        let currentSummary = cacheSummary()
        let updatedSummary = RemoteThumbnailCacheSummary(
            fileCount: currentSummary.fileCount + (previousSize == nil ? 1 : 0),
            totalBytes: max(0, currentSummary.totalBytes - (previousSize ?? 0) + newSize)
        )

        let shouldScheduleTrim = withSummaryLock {
            cachedSummary = updatedSummary

            guard updatedSummary.fileCount > maximumCachedThumbnailCount
                    || updatedSummary.totalBytes > maximumTotalCacheBytes
            else {
                return false
            }

            guard !trimScheduled else {
                return false
            }

            trimScheduled = true
            return true
        }

        guard shouldScheduleTrim else {
            return
        }

        maintenanceQueue.async { [weak self] in
            self?.performTrimMaintenance()
        }
    }

    nonisolated private func performTrimMaintenance() {
        let trimmedSummary = trimCacheIfNeeded()

        let shouldScheduleAnotherPass = withSummaryLock {
            cachedSummary = trimmedSummary
            trimScheduled = false

            guard trimmedSummary.fileCount > maximumCachedThumbnailCount
                    || trimmedSummary.totalBytes > maximumTotalCacheBytes
            else {
                return false
            }

            trimScheduled = true
            return true
        }

        guard shouldScheduleAnotherPass else {
            return
        }

        maintenanceQueue.async { [weak self] in
            self?.performTrimMaintenance()
        }
    }

    nonisolated private func scanSummaryFromDisk() -> RemoteThumbnailCacheSummary {
        let cachedFiles = enumerateCachedFiles()
        let totalBytes = cachedFiles.reduce(into: Int64.zero) { partialResult, record in
            partialResult += record.size
        }
        return RemoteThumbnailCacheSummary(
            fileCount: cachedFiles.count,
            totalBytes: totalBytes
        )
    }

    nonisolated private func trimCacheIfNeeded() -> RemoteThumbnailCacheSummary {
        var cachedFiles = enumerateCachedFiles()
        let totalBytes = cachedFiles.reduce(into: Int64.zero) { partialResult, record in
            partialResult += record.size
        }

        guard cachedFiles.count > maximumCachedThumbnailCount || totalBytes > maximumTotalCacheBytes else {
            return RemoteThumbnailCacheSummary(fileCount: cachedFiles.count, totalBytes: totalBytes)
        }

        cachedFiles.sort { lhs, rhs in
            lhs.lastAccessDate < rhs.lastAccessDate
        }

        var remainingCount = cachedFiles.count
        var remainingBytes = totalBytes

        for candidate in cachedFiles {
            guard remainingCount > maximumCachedThumbnailCount
                    || remainingBytes > maximumTotalCacheBytes
            else {
                break
            }

            try? fileManager.removeItem(at: candidate.url)
            remainingCount -= 1
            remainingBytes -= candidate.size
        }

        return RemoteThumbnailCacheSummary(
            fileCount: max(0, remainingCount),
            totalBytes: max(0, remainingBytes)
        )
    }

    nonisolated private func enumerateCachedFiles() -> [CachedThumbnailFileRecord] {
        guard fileManager.fileExists(atPath: cacheRootURL.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: cacheRootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var cachedFiles: [CachedThumbnailFileRecord] = []
        cachedFiles.reserveCapacity(256)

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else {
                continue
            }

            cachedFiles.append(
                CachedThumbnailFileRecord(
                    url: fileURL,
                    size: Int64(values?.fileSize ?? 0),
                    lastAccessDate: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        return cachedFiles
    }

    nonisolated private func withSummaryLock<T>(_ body: () -> T) -> T {
        summaryLock.lock()
        defer { summaryLock.unlock() }
        return body()
    }

}

private struct RemoteComicThumbnailWorker {
    let diskCache: RemoteThumbnailDiskCacheStore

    nonisolated func buildThumbnail(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        browsingService: RemoteServerBrowsingService,
        maxPixelSize: Int,
        diskURL: URL
    ) async -> UIImage? {
        if let remoteImage = await browsingService.fetchDirectThumbnail(
            for: profile,
            reference: reference,
            maxPixelSize: maxPixelSize
        ) {
            if let thumbnailData = Self.encodedThumbnailData(from: remoteImage) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return remoteImage
        }

        if let cachedFileURL = await browsingService.cachedFileURLIfAvailable(for: reference),
           let cachedImage = await Self.extractThumbnail(from: cachedFileURL, maxPixelSize: maxPixelSize) {
            if let thumbnailData = Self.encodedThumbnailData(from: cachedImage) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return cachedImage
        }

        do {
            let downloadResult = try await browsingService.downloadComicFile(
                for: profile,
                reference: reference
            )

            guard !Task.isCancelled,
                  let image = await Self.extractThumbnail(
                    from: downloadResult.localFileURL,
                    maxPixelSize: maxPixelSize
                  ) else {
                return nil
            }

            if let thumbnailData = Self.encodedThumbnailData(from: image) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return image
        } catch {
            return nil
        }
    }

    nonisolated private static func extractThumbnail(from fileURL: URL, maxPixelSize: Int) async -> UIImage? {
        let extractor = await LibraryComicMetadataExtractor()
        guard let metadata = try? await extractor.extractMetadata(for: fileURL),
              let coverImage = metadata.coverImage
        else {
            return nil
        }

        return downsampledImage(from: coverImage, maxPixelSize: maxPixelSize)
    }

    nonisolated private static func downsampledImage(from image: UIImage, maxPixelSize: Int) -> UIImage {
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

    nonisolated private static func encodedThumbnailData(from image: UIImage) -> Data? {
        if let jpegData = image.jpegData(compressionQuality: 0.82) {
            return jpegData
        }

        return image.pngData()
    }
}
