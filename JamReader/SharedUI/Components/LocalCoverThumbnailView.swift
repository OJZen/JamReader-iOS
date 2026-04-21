import Combine
import ImageIO
import SwiftUI
import UIKit

struct LocalComicCoverSource: Hashable {
    let fileURL: URL
    let cacheURL: URL?
}

struct LocalCoverThumbnailView: View {
    let url: URL?
    let fallbackSource: LocalComicCoverSource?
    let placeholderSystemName: String
    let transitionKey: String?
    let heroSourceID: String?
    let width: CGFloat
    let height: CGFloat

    init(
        url: URL?,
        fallbackSource: LocalComicCoverSource? = nil,
        placeholderSystemName: String,
        transitionKey: String? = nil,
        heroSourceID: String? = nil,
        width: CGFloat = 56,
        height: CGFloat = 78
    ) {
        self.url = url
        self.fallbackSource = fallbackSource
        self.placeholderSystemName = placeholderSystemName
        self.transitionKey = transitionKey
        self.heroSourceID = heroSourceID
        self.width = width
        self.height = height
    }

    var body: some View {
        ThumbnailView(
            loader: LocalCoverLoader(),
            placeholderSystemName: placeholderSystemName,
            width: width,
            height: height,
            cornerRadius: 12,
            contentID: Self.contentID(for: url, fallbackSource: fallbackSource)
        ) { loader, targetSize, scale in
            loader.load(
                from: url,
                fallbackSource: fallbackSource,
                transitionKey: transitionKey,
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

    private static func contentID(
        for url: URL?,
        fallbackSource: LocalComicCoverSource?
    ) -> String {
        if let url {
            return fileIdentity(for: url, prefix: "url")
        }

        if let fallbackSource {
            if let cacheURL = fallbackSource.cacheURL,
               FileManager.default.fileExists(atPath: cacheURL.path) {
                return fileIdentity(for: cacheURL, prefix: "fallback-cache")
            }

            return fileIdentity(for: fallbackSource.fileURL, prefix: "fallback-source")
        }

        return "nil"
    }

    private static func fileIdentity(for url: URL, prefix: String) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(prefix):\(url.path)#\(fileSize)#\(Int(modificationTime))"
    }
}

@MainActor
private final class LocalCoverLoader: ObservableObject, ThumbnailLoading {
    @Published private(set) var image: UIImage?
    private var loadTask: Task<Void, Never>?
    private var requestID: String?

    func load(
        from url: URL?,
        fallbackSource: LocalComicCoverSource?,
        transitionKey: String?,
        targetSize: CGSize,
        scale: CGFloat
    ) {
        loadTask?.cancel()

        guard url != nil || fallbackSource != nil else {
            requestID = nil
            image = nil
            return
        }

        let maxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let requestID = "\(Self.requestIdentity(url: url, fallbackSource: fallbackSource))#\(maxPixelSize)"

        if self.requestID != requestID {
            image = nil
        }

        self.requestID = requestID
        loadTask = Task { [weak self] in
            let image = await LocalCoverImagePipeline.shared.image(
                for: url,
                fallbackSource: fallbackSource,
                maxPixelSize: maxPixelSize
            )

            guard let self, !Task.isCancelled, self.requestID == requestID else {
                return
            }

            self.image = image
            if let image, let transitionKey {
                LocalCoverTransitionCache.shared.store(image, for: transitionKey)
            }
        }
    }

    private static func requestIdentity(
        url: URL?,
        fallbackSource: LocalComicCoverSource?
    ) -> String {
        if let url {
            return url.path
        }

        if let fallbackSource {
            return fallbackSource.cacheURL?.path ?? fallbackSource.fileURL.path
        }

        return "nil"
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
final class LocalCoverTransitionCache {
    static let shared = LocalCoverTransitionCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let nsKey = key as NSString
        if let existing = cache.object(forKey: nsKey) {
            let existingPixels = existing.size.width * existing.scale * existing.size.height * existing.scale
            let newPixels = image.size.width * image.scale * image.size.height * image.scale
            guard newPixels >= existingPixels else {
                return
            }
        }

        cache.setObject(image, forKey: nsKey, cost: Self.cacheCost(for: image))
    }

    func clear() {
        cache.removeAllObjects()
    }

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}

actor LocalCoverImagePipeline {
    static let shared = LocalCoverImagePipeline()
    private static let semaphore = AsyncSemaphore(maxConcurrent: 4)

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func image(
        for url: URL?,
        fallbackSource: LocalComicCoverSource?,
        maxPixelSize: Int
    ) async -> UIImage? {
        guard let cacheDescriptor = Self.cacheDescriptor(
            url: url,
            fallbackSource: fallbackSource
        ) else {
            return nil
        }

        let cacheKey = Self.cacheKey(
            identity: cacheDescriptor.identity,
            resourceURL: cacheDescriptor.resourceURL,
            maxPixelSize: maxPixelSize
        )
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            return cachedImage
        }

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let task = Task.detached(priority: .utility) {
            await Self.semaphore.run {
                await Self.loadImage(
                    from: url,
                    fallbackSource: fallbackSource,
                    maxPixelSize: maxPixelSize
                )
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

    func clearMemoryCache() {
        cache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
    }

    private static func cacheKey(
        identity: String,
        resourceURL: URL,
        maxPixelSize: Int
    ) -> String {
        let resourceValues = try? resourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = resourceValues?.fileSize ?? 0
        return "\(identity)#\(fileSize)#\(Int(modificationTime))#\(maxPixelSize)"
    }

    private static func cacheDescriptor(
        url: URL?,
        fallbackSource: LocalComicCoverSource?
    ) -> (identity: String, resourceURL: URL)? {
        if let url {
            return (url.path, url)
        }

        if let fallbackSource,
           let cacheURL = fallbackSource.cacheURL,
           FileManager.default.fileExists(atPath: cacheURL.path) {
            return ("cached:\(cacheURL.path)", cacheURL)
        }

        if let fallbackSource {
            return ("source:\(fallbackSource.fileURL.path)", fallbackSource.fileURL)
        }

        return nil
    }

    private static func loadImage(
        from url: URL?,
        fallbackSource: LocalComicCoverSource?,
        maxPixelSize: Int
    ) async -> UIImage? {
        if let url {
            return loadDownsampledImage(from: url, maxPixelSize: maxPixelSize)
        }

        guard let fallbackSource else {
            return nil
        }

        if let cacheURL = fallbackSource.cacheURL,
           FileManager.default.fileExists(atPath: cacheURL.path) {
            return loadDownsampledImage(from: cacheURL, maxPixelSize: maxPixelSize)
        }

        return await loadGeneratedCoverImage(
            from: fallbackSource,
            maxPixelSize: maxPixelSize
        )
    }

    private static func loadGeneratedCoverImage(
        from fallbackSource: LocalComicCoverSource,
        maxPixelSize: Int
    ) async -> UIImage? {
        let extractedCover = await MainActor.run { () -> (coverImage: UIImage, cacheURL: URL?)? in
            let extractor = LibraryComicMetadataExtractor()
            guard let metadata = try? extractor.extractMetadata(for: fallbackSource.fileURL),
                  let coverImage = metadata.coverImage else {
                return nil
            }

            if let cacheURL = fallbackSource.cacheURL {
                try? extractor.saveCover(coverImage, to: cacheURL)
                return (coverImage, cacheURL)
            }

            return (coverImage, nil)
        }

        guard let extractedCover else {
            return nil
        }

        if let cacheURL = extractedCover.cacheURL {
            if let cachedImage = loadDownsampledImage(from: cacheURL, maxPixelSize: maxPixelSize) {
                return cachedImage
            }
        }

        return downsampledImage(from: extractedCover.coverImage, maxPixelSize: maxPixelSize)
    }

    private static func loadDownsampledImage(from url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return UIImage(contentsOfFile: url.path)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) {
            return UIImage(cgImage: thumbnail)
        }

        return UIImage(contentsOfFile: url.path)
    }

    private static func downsampledImage(from image: UIImage, maxPixelSize: Int) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else {
            return image
        }

        let scale = min(CGFloat(maxPixelSize) / longestSide, 1)
        guard scale < 0.999 else {
            return image
        }

        let targetSize = CGSize(
            width: max(image.size.width * scale, 1),
            height: max(image.size.height * scale, 1)
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
}
