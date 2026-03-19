import Combine
import SwiftUI
import UIKit

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
private final class RemoteComicThumbnailPipeline {
    static let shared = RemoteComicThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
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

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let downloadResult = try await browsingService.downloadComicFile(
                    for: profile,
                    reference: reference
                )

                if Task.isCancelled {
                    return nil
                }

                return Self.extractThumbnail(
                    from: downloadResult.localFileURL,
                    maxPixelSize: maxPixelSize
                )
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
}
