import Combine
import CryptoKit
import ImageIO
import PDFKit
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
    let profile: RemoteServerProfile
    let item: RemoteDirectoryItem
    let browsingService: RemoteServerBrowsingService
    let placeholderSystemName: String
    let prefersLocalCache: Bool
    let allowsRemoteFetch: Bool
    let heroSourceID: String?
    let width: CGFloat
    let height: CGFloat

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        placeholderSystemName: String = "doc.richtext",
        prefersLocalCache: Bool = false,
        allowsRemoteFetch: Bool = true,
        heroSourceID: String? = nil,
        width: CGFloat = 74,
        height: CGFloat = 104
    ) {
        self.profile = profile
        self.item = item
        self.browsingService = browsingService
        self.placeholderSystemName = placeholderSystemName
        self.prefersLocalCache = prefersLocalCache
        self.allowsRemoteFetch = allowsRemoteFetch
        self.heroSourceID = heroSourceID
        self.width = width
        self.height = height
    }

    var body: some View {
        ThumbnailView(
            loader: RemoteComicThumbnailLoader(),
            placeholderSystemName: placeholderSystemName,
            width: width,
            height: height,
            cornerRadius: 14,
            contentID: item.id
        ) { loader, targetSize, scale in
            loader.load(
                profile: profile,
                item: item,
                browsingService: browsingService,
                prefersLocalCache: prefersLocalCache,
                allowsRemoteFetch: allowsRemoteFetch,
                targetSize: targetSize,
                scale: scale
            )
        }
        .overlay {
            if let heroSourceID {
                HeroSourceAnchorView(id: heroSourceID)
                    .allowsHitTesting(false)
            }
        }
    }
}

@MainActor
private final class RemoteComicThumbnailLoader: ObservableObject, ThumbnailLoading {
    @Published private(set) var image: UIImage?
    private var loadTask: Task<Void, Never>?
    private var requestID: String?
    // Tracks item identity separately from size so we only clear the displayed
    // image when the item changes — not when the caller switches between grid
    // (208 px) and list (76 px) for the same item.
    private var loadedItemID: String?

    func load(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool,
        allowsRemoteFetch: Bool,
        targetSize: CGSize,
        scale: CGFloat
    ) {
        guard item.canOpenAsComic else {
            loadTask?.cancel()
            requestID = nil
            loadedItemID = nil
            image = nil
            return
        }

        let requestedMaxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let normalizedMaxPixelSize = RemoteComicThumbnailPipeline.normalizedPixelSize(
            for: requestedMaxPixelSize
        )
        let requestID = "\(item.id)#\(normalizedMaxPixelSize)"
        let itemID = "\(item.id)#\(item.fileSize ?? 0)"

        if self.requestID == requestID,
           self.loadedItemID == itemID,
           image != nil || loadTask != nil {
            return
        }

        loadTask?.cancel()

        let seededImage = RemoteComicThumbnailPipeline.shared.cachedImage(
            for: item,
            browsingService: browsingService,
            maxPixelSize: normalizedMaxPixelSize
        )

        if self.loadedItemID != itemID {
            image = seededImage
        } else if image == nil {
            image = seededImage
        }
        // Same item, different size — keep existing image visible until new size arrives

        self.requestID = requestID
        self.loadedItemID = itemID
        loadTask = Task { [weak self] in
            let image = await RemoteComicThumbnailPipeline.shared.image(
                for: profile,
                item: item,
                browsingService: browsingService,
                prefersLocalCache: prefersLocalCache,
                maxPixelSize: normalizedMaxPixelSize,
                allowsRemoteFetch: allowsRemoteFetch
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
    private static let semaphore = AsyncSemaphore(maxConcurrent: 6)

    private let cache = NSCache<NSString, UIImage>()
    // Secondary cache keyed by item identity (no pixel size).
    // Stores the highest-quality (largest) image fetched for each item so that
    // switching from grid to list can downsample from this cache instead of
    // re-fetching from the network.
    private let highQualityCache = NSCache<NSString, UIImage>()
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
            .appendingPathComponent("JamReader", isDirectory: true)
            .appendingPathComponent("RemoteThumbnails", isDirectory: true)
        self.diskCache = RemoteThumbnailDiskCacheStore(
            fileManager: fileManager,
            cacheRootURL: thumbnailCacheRootURL,
            maximumCachedThumbnailCount: maximumCachedThumbnailCount,
            maximumTotalCacheBytes: maximumTotalCacheBytes
        )
        cache.countLimit = 384
        cache.totalCostLimit = 96 * 1_024 * 1_024
        // Smaller limit for the HQ cache — it stores at most one image per item
        // (the largest fetched size) and memory cost is higher per entry.
        highQualityCache.countLimit = 256
        highQualityCache.totalCostLimit = 72 * 1_024 * 1_024
    }

    func image(
        for profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool = false,
        maxPixelSize: Int,
        allowsRemoteFetch: Bool = true
    ) async -> UIImage? {
        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item)
        else {
            return nil
        }

        let requestedMaxPixelSize = maxPixelSize
        let maxPixelSize = Self.normalizedPixelSize(for: requestedMaxPixelSize)
        let cacheKey = Self.cacheKey(for: reference, maxPixelSize: maxPixelSize)
        let requestKey = Self.requestKey(forCacheKey: cacheKey, allowsRemoteFetch: allowsRemoteFetch)
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            promoteToTransitionCache(cachedImage, for: reference)
            return cachedImage
        }

        // Disk check runs on the maintenance queue — never blocks the main thread.
        let diskURL = cachedThumbnailURL(forCacheKey: cacheKey)
        if let diskCachedImage = await diskCache.loadCachedImageAsync(at: diskURL) {
            cache.setObject(
                diskCachedImage,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: diskCachedImage)
            )
            promoteToTransitionCache(diskCachedImage, for: reference)
            diskCache.touchCachedThumbnail(at: diskURL)
            return diskCachedImage
        }

        if requestedMaxPixelSize != maxPixelSize {
            let legacyCacheKey = Self.cacheKey(for: reference, maxPixelSize: requestedMaxPixelSize)
            let legacyNSCacheKey = legacyCacheKey as NSString

            if let legacyCachedImage = cache.object(forKey: legacyNSCacheKey) {
                cache.setObject(
                    legacyCachedImage,
                    forKey: nsCacheKey,
                    cost: Self.cacheCost(for: legacyCachedImage)
                )
                promoteToTransitionCache(legacyCachedImage, for: reference)
                return legacyCachedImage
            }

            let legacyDiskURL = cachedThumbnailURL(forCacheKey: legacyCacheKey)
            if let legacyDiskCachedImage = await diskCache.loadCachedImageAsync(at: legacyDiskURL) {
                cache.setObject(
                    legacyDiskCachedImage,
                    forKey: nsCacheKey,
                    cost: Self.cacheCost(for: legacyDiskCachedImage)
                )
                promoteToTransitionCache(legacyDiskCachedImage, for: reference)
                if let thumbnailData = Self.encodedThumbnailData(from: legacyDiskCachedImage) {
                    try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
                }
                diskCache.touchCachedThumbnail(at: legacyDiskURL)
                return legacyDiskCachedImage
            }
        }

        // Before going to the network, check whether we already have a larger version
        // of this item in the high-quality cache (e.g. the grid loaded 416 px and now
        // the list wants 152 px). Avoid synchronous renderer work on the main actor
        // while the list is scrolling; the HQ image is already decoded and cheap to
        // scale down at display time.
        let hqKey = Self.itemQualityCacheKey(for: reference) as NSString
        if let hqImage = highQualityCache.object(forKey: hqKey),
           Self.pixelSize(for: hqImage) >= maxPixelSize {
            return hqImage
        }

        if let inFlightTask = inFlightTasks[requestKey] {
            return await inFlightTask.value
        }

        let worker = RemoteComicThumbnailWorker(
            diskCache: diskCache
        )
        let task = Task<UIImage?, Never> {
            await Self.semaphore.run {
                await worker.buildThumbnail(
                    for: profile,
                    reference: reference,
                    browsingService: browsingService,
                    prefersLocalCache: prefersLocalCache,
                    maxPixelSize: maxPixelSize,
                    diskURL: diskURL,
                    allowsRemoteFetch: allowsRemoteFetch
                )
            }
        }

        inFlightTasks[requestKey] = task
        let image = await task.value
        inFlightTasks[requestKey] = nil

        if let image {
            cache.setObject(
                image,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: image)
            )
            promoteToTransitionCache(image, for: reference)
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

    func cachedTransitionImage(
        for item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService
    ) -> UIImage? {
        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item)
        else {
            return nil
        }

        let cacheKey = Self.itemQualityCacheKey(for: reference) as NSString
        return highQualityCache.object(forKey: cacheKey)
    }

    func cachedImage(
        for item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService,
        maxPixelSize: Int
    ) -> UIImage? {
        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item)
        else {
            return nil
        }

        let requestedMaxPixelSize = maxPixelSize
        let maxPixelSize = Self.normalizedPixelSize(for: requestedMaxPixelSize)
        let cacheKey = Self.cacheKey(for: reference, maxPixelSize: maxPixelSize)
        let nsCacheKey = cacheKey as NSString

        // Memory-only fast path — no disk I/O on the main thread.
        // The async image(for:) method handles disk + network and will
        // update the displayed image once it resolves.

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            promoteToTransitionCache(cachedImage, for: reference)
            return cachedImage
        }

        if requestedMaxPixelSize != maxPixelSize {
            let legacyCacheKey = Self.cacheKey(for: reference, maxPixelSize: requestedMaxPixelSize)
            if let legacyCachedImage = cache.object(forKey: legacyCacheKey as NSString) {
                cache.setObject(legacyCachedImage, forKey: nsCacheKey, cost: Self.cacheCost(for: legacyCachedImage))
                promoteToTransitionCache(legacyCachedImage, for: reference)
                return legacyCachedImage
            }
        }

        let hqKey = Self.itemQualityCacheKey(for: reference) as NSString
        if let hqImage = highQualityCache.object(forKey: hqKey),
           Self.pixelSize(for: hqImage) >= maxPixelSize {
            return hqImage
        }

        return nil
    }

    func hasCachedThumbnail(
        for item: RemoteDirectoryItem,
        browsingService: RemoteServerBrowsingService
    ) -> Bool {
        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item)
        else {
            return false
        }

        return hasCachedThumbnail(for: reference)
    }

    func preheat(
        for profile: RemoteServerProfile,
        items: [RemoteDirectoryItem],
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool = false,
        maxPixelSize: Int,
        limit: Int,
        skipCount: Int = 0,
        concurrency: Int,
        allowsRemoteFetch: Bool = false
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

        let workItems = candidates.map { item in
            let itemPrefersLocalCache: Bool
            if let reference = try? browsingService.makeComicFileReference(from: item) {
                itemPrefersLocalCache = prefersLocalCache
                    || browsingService.cachedAvailability(for: reference).hasLocalCopy
            } else {
                itemPrefersLocalCache = prefersLocalCache
            }

            return (item: item, prefersLocalCache: itemPrefersLocalCache)
        }

        let maximumConcurrency = max(1, min(concurrency, workItems.count))
        var nextIndex = 0

        await withTaskGroup(of: Void.self) { group in
            func enqueueNextIfNeeded() {
                guard nextIndex < workItems.count else {
                    return
                }

                let workItem = workItems[nextIndex]
                nextIndex += 1
                let taskPriority: TaskPriority = allowsRemoteFetch ? .utility : .background

                group.addTask(priority: taskPriority) { [weak self] in
                    guard let self else {
                        return
                    }

                    _ = await self.image(
                        for: profile,
                        item: workItem.item,
                        browsingService: browsingService,
                        prefersLocalCache: workItem.prefersLocalCache,
                        maxPixelSize: maxPixelSize,
                        allowsRemoteFetch: allowsRemoteFetch
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

    private static func requestKey(forCacheKey cacheKey: String, allowsRemoteFetch: Bool) -> String {
        "\(cacheKey)#remote:\(allowsRemoteFetch ? 1 : 0)"
    }

    // Cache key that identifies an item regardless of requested pixel size.
    private static func itemQualityCacheKey(for reference: RemoteComicFileReference) -> String {
        let modifiedAt = Int(reference.modifiedAt?.timeIntervalSince1970 ?? 0)
        return "\(reference.id)#\(reference.fileSize ?? 0)#\(modifiedAt)"
    }

    static func normalizedPixelSize(for requestedPixelSize: Int) -> Int {
        let clampedPixelSize = min(max(160, requestedPixelSize), 512)

        switch clampedPixelSize {
        case ...160:
            return 160
        case ...256:
            return 256
        case ...384:
            return 384
        default:
            return 512
        }
    }

    private static func downsampledImage(from source: UIImage, maxPixelSize: Int) -> UIImage {
        let maxDim = max(source.size.width, source.size.height) * source.scale
        guard maxDim > CGFloat(maxPixelSize) else { return source }
        let scale = CGFloat(maxPixelSize) / maxDim
        let newSize = CGSize(
            width: (source.size.width * source.scale * scale).rounded(),
            height: (source.size.height * source.scale * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }

    private static func pixelSize(for image: UIImage) -> Int {
        Int(max(image.size.width, image.size.height) * image.scale)
    }

    private static func encodedThumbnailData(from image: UIImage) -> Data? {
        if let jpegData = image.jpegData(compressionQuality: 0.82) {
            return jpegData
        }

        return image.pngData()
    }

    private func promoteToTransitionCache(_ image: UIImage, for reference: RemoteComicFileReference) {
        let hqKey = Self.itemQualityCacheKey(for: reference) as NSString
        let newPixels = Self.pixelSize(for: image)

        if let existing = highQualityCache.object(forKey: hqKey) {
            let existingPixels = Self.pixelSize(for: existing)
            guard newPixels > existingPixels else {
                return
            }
        }

        highQualityCache.setObject(image, forKey: hqKey, cost: Self.cacheCost(for: image))
    }

    private func cachedThumbnailURL(forCacheKey cacheKey: String) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return thumbnailCacheRootURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func hasCachedThumbnail(for reference: RemoteComicFileReference) -> Bool {
        let qualityCacheKey = Self.itemQualityCacheKey(for: reference) as NSString
        if highQualityCache.object(forKey: qualityCacheKey) != nil {
            return true
        }

        for pixelSize in [160, 256, 384, 512] {
            let cacheKey = Self.cacheKey(for: reference, maxPixelSize: pixelSize) as NSString
            if cache.object(forKey: cacheKey) != nil {
                return true
            }

            let diskURL = cachedThumbnailURL(
                forCacheKey: Self.cacheKey(for: reference, maxPixelSize: pixelSize)
            )
            if fileManager.fileExists(atPath: diskURL.path) {
                return true
            }
        }

        return false
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
    private let touchStateLock = NSLock()
    private let maintenanceQueue = DispatchQueue(
        label: "JamReader.RemoteThumbnailDiskCacheMaintenance",
        qos: .utility
    )
    private let minimumTouchInterval: TimeInterval = 6 * 60 * 60

    nonisolated(unsafe) private var cachedSummary: RemoteThumbnailCacheSummary?
    nonisolated(unsafe) private var trimScheduled = false
    nonisolated(unsafe) private var recentTouchDatesByPath: [String: Date] = [:]

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
        withTouchStateLock {
            recentTouchDatesByPath.removeAll()
        }
    }

    nonisolated func loadCachedImage(at fileURL: URL) -> UIImage? {
        decodedCachedImage(at: fileURL)
    }

    /// Async variant — performs the disk read on the maintenance queue so the
    /// caller's thread (typically the main actor) is never blocked by file I/O.
    nonisolated func loadCachedImageAsync(at fileURL: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            maintenanceQueue.async { [self] in
                continuation.resume(returning: decodedCachedImage(at: fileURL))
            }
        }
    }

    nonisolated private func decodedCachedImage(at fileURL: URL) -> UIImage? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return UIImage(contentsOfFile: fileURL.path)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ]

        guard let decodedThumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return UIImage(contentsOfFile: fileURL.path)
        }

        return UIImage(cgImage: decodedThumbnail)
    }

    nonisolated func storeEncodedThumbnailData(_ data: Data, at fileURL: URL) throws {
        let previousSize = cachedFileSize(at: fileURL)

        try fileManager.createDirectory(
            at: cacheRootURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        recordTouch(at: fileURL, at: Date())
        let newSize = DiskUsageScanner.allocatedByteCount(at: fileURL, fileManager: fileManager)

        updateSummaryAfterStore(
            previousSize: previousSize,
            newSize: newSize
        )
    }

    nonisolated func touchCachedThumbnail(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        let now = Date()
        guard shouldScheduleTouch(for: fileURL.path, now: now) else {
            return
        }
    }

    nonisolated private func cachedFileSize(at fileURL: URL) -> Int64? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return DiskUsageScanner.allocatedByteCount(at: fileURL, fileManager: fileManager)
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
                forKeys: [
                    .isRegularFileKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]
            )
            guard values?.isRegularFile == true else {
                continue
            }

            let persistedAccessDate = values?.contentModificationDate ?? .distantPast
            let inMemoryAccessDate = withTouchStateLock {
                recentTouchDatesByPath[fileURL.path]
            } ?? .distantPast

            cachedFiles.append(
                CachedThumbnailFileRecord(
                    url: fileURL,
                    size: DiskUsageScanner.allocatedByteCount(at: fileURL, fileManager: fileManager),
                    lastAccessDate: max(persistedAccessDate, inMemoryAccessDate)
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

    nonisolated private func shouldScheduleTouch(for path: String, now: Date) -> Bool {
        withTouchStateLock {
            if let lastTouch = recentTouchDatesByPath[path],
               now.timeIntervalSince(lastTouch) < minimumTouchInterval {
                return false
            }

            recentTouchDatesByPath[path] = now

            if recentTouchDatesByPath.count > 2048 {
                let cutoffDate = now.addingTimeInterval(-minimumTouchInterval * 2)
                recentTouchDatesByPath = recentTouchDatesByPath.filter { _, date in
                    date >= cutoffDate
                }
            }

            return true
        }
    }

    nonisolated private func recordTouch(at fileURL: URL, at date: Date) {
        withTouchStateLock {
            recentTouchDatesByPath[fileURL.path] = date
        }
    }

    nonisolated private func clearRecordedTouch(for path: String) {
        _ = withTouchStateLock {
            recentTouchDatesByPath.removeValue(forKey: path)
        }
    }

    nonisolated private func withTouchStateLock<T>(_ body: () -> T) -> T {
        touchStateLock.lock()
        defer { touchStateLock.unlock() }
        return body()
    }

}

private struct RemoteComicThumbnailWorker {
    let diskCache: RemoteThumbnailDiskCacheStore

    nonisolated func buildThumbnail(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        browsingService: RemoteServerBrowsingService,
        prefersLocalCache: Bool,
        maxPixelSize: Int,
        diskURL: URL,
        allowsRemoteFetch: Bool
    ) async -> UIImage? {
        guard !Task.isCancelled else {
            return nil
        }

        let isEBookDocument = EBookDocumentSupport.supportsFileExtension(reference.fileExtension)

        if reference.isPDFDocument {
            guard let cachedFileURL = await browsingService.cachedFileURLIfAvailable(for: reference),
                  let cachedImage = await Self.extractLocalPDFThumbnail(
                    from: cachedFileURL,
                    maxPixelSize: maxPixelSize
                  ) else {
                return nil
            }

            if let thumbnailData = Self.encodedThumbnailData(from: cachedImage) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return cachedImage
        }

        if isEBookDocument {
            guard let cachedFileURL = await browsingService.cachedFileURLIfAvailable(for: reference),
                  let cachedImage = await Self.extractThumbnail(from: cachedFileURL, maxPixelSize: maxPixelSize)
            else {
                return nil
            }

            if let thumbnailData = Self.encodedThumbnailData(from: cachedImage) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return cachedImage
        }

        if prefersLocalCache,
           let cachedFileURL = await browsingService.cachedFileURLIfAvailable(for: reference),
           let cachedImage = await Self.extractThumbnail(from: cachedFileURL, maxPixelSize: maxPixelSize) {
            if let thumbnailData = Self.encodedThumbnailData(from: cachedImage) {
                try? diskCache.storeEncodedThumbnailData(thumbnailData, at: diskURL)
            }
            return cachedImage
        }

        let remoteFetchAllowedByServer = await browsingService.allowsRemoteThumbnailFetch(
            for: profile,
            reference: reference
        )
        let canAttemptRemoteFetch = allowsRemoteFetch && remoteFetchAllowedByServer

        if canAttemptRemoteFetch,
           let remoteImage = await browsingService.fetchDirectThumbnail(
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

        return nil
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

    nonisolated private static func extractLocalPDFThumbnail(
        from fileURL: URL,
        maxPixelSize: Int
    ) async -> UIImage? {
        await LocalPDFBrowserThumbnailExtractor.shared.thumbnail(
            from: fileURL,
            maxPixelSize: maxPixelSize
        )
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

private final class LocalPDFBrowserThumbnailExtractor: @unchecked Sendable {
    static let shared = LocalPDFBrowserThumbnailExtractor()

    private let extractionQueue = DispatchQueue(
        label: "JamReader.LocalPDFBrowserThumbnailExtractor",
        qos: .utility
    )

    nonisolated func thumbnail(from fileURL: URL, maxPixelSize: Int) async -> UIImage? {
        await withCheckedContinuation { continuation in
            extractionQueue.async {
                let image = autoreleasepool { () -> UIImage? in
                    guard let document = PDFDocument(url: fileURL),
                          document.pageCount > 0,
                          let page = document.page(at: 0) else {
                        return nil
                    }

                    let clampedPixelSize = max(1, min(maxPixelSize, 512))
                    let targetSize = CGSize(width: clampedPixelSize, height: clampedPixelSize)
                    let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
                    guard thumbnail.size.width > 0, thumbnail.size.height > 0 else {
                        return nil
                    }

                    return thumbnail
                }

                continuation.resume(returning: image)
            }
        }
    }
}
