import Combine
import ImageIO
import SwiftUI
import UIKit

struct LocalCoverThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let url: URL?
    let placeholderSystemName: String
    let width: CGFloat
    let height: CGFloat

    @StateObject private var loader = LocalCoverLoader()

    init(
        url: URL?,
        placeholderSystemName: String,
        width: CGFloat = 56,
        height: CGFloat = 78
    ) {
        self.url = url
        self.placeholderSystemName = placeholderSystemName
        self.width = width
        self.height = height
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .task(id: loaderRequestID) {
            loader.load(
                from: url,
                targetSize: CGSize(width: width, height: height),
                scale: displayScale
            )
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var loaderRequestID: String {
        let path = url?.path ?? "nil"
        return "\(path)#\(Int(width))x\(Int(height))@\(Int(displayScale * 100))"
    }
}

@MainActor
private final class LocalCoverLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var loadTask: Task<Void, Never>?
    private var requestID: String?

    func load(from url: URL?, targetSize: CGSize, scale: CGFloat) {
        loadTask?.cancel()

        guard let url else {
            requestID = nil
            image = nil
            return
        }

        let maxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let requestID = "\(url.path)#\(maxPixelSize)"

        if self.requestID != requestID {
            image = nil
        }

        self.requestID = requestID
        loadTask = Task { [weak self] in
            let image = await LocalCoverImagePipeline.shared.image(
                for: url,
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

private actor LocalCoverImagePipeline {
    static let shared = LocalCoverImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(for url: URL, maxPixelSize: Int) async -> UIImage? {
        let cacheKey = Self.cacheKey(for: url, maxPixelSize: maxPixelSize)
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            return cachedImage
        }

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let task = Task.detached(priority: .utility) {
            Self.loadDownsampledImage(
                from: url,
                maxPixelSize: maxPixelSize
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

    private static func cacheKey(for url: URL, maxPixelSize: Int) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = resourceValues?.fileSize ?? 0
        return "\(url.path)#\(fileSize)#\(Int(modificationTime))#\(maxPixelSize)"
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

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}
