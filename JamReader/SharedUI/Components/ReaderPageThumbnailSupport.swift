import Combine
import ImageIO
import PDFKit
import SwiftUI
import UIKit

enum ReaderPageThumbnailStyle {
    case browser
    case scrubber
    case floatingPreview
}

extension Notification.Name {
    nonisolated static let readerPagePreviewDidUpdate = Notification.Name("ReaderPagePreviewDidUpdate")
}

enum ReaderPagePreviewNotificationUserInfoKey {
    nonisolated static let namespace = "namespace"
    nonisolated static let pageIndex = "pageIndex"
}

nonisolated func readerPagePreviewUpdateInfo(from notification: Notification) -> (namespace: String, pageIndex: Int)? {
    guard let namespace = notification.userInfo?[ReaderPagePreviewNotificationUserInfoKey.namespace] as? String,
          let pageIndex = notification.userInfo?[ReaderPagePreviewNotificationUserInfoKey.pageIndex] as? Int
    else {
        return nil
    }

    return (namespace, pageIndex)
}

nonisolated func readerPagePreviewNotificationMatches(
    _ notification: Notification,
    namespace: String,
    pageIndex: Int
) -> Bool {
    guard let info = readerPagePreviewUpdateInfo(from: notification) else {
        return false
    }

    return info.namespace == namespace && info.pageIndex == pageIndex
}

final class ReaderPagePreviewEntry: NSObject {
    let image: UIImage
    let pixelSize: Int

    nonisolated init(image: UIImage, pixelSize: Int) {
        self.image = image
        self.pixelSize = pixelSize
    }
}

final class ReaderPagePreviewStore: @unchecked Sendable {
    nonisolated static let shared = ReaderPagePreviewStore()

    nonisolated(unsafe) private let cache = NSCache<NSString, ReaderPagePreviewEntry>()
    private let lock = NSLock()

    nonisolated private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    nonisolated func entry(namespace: String, pageIndex: Int) -> ReaderPagePreviewEntry? {
        let cacheKey = cacheKey(namespace: namespace, pageIndex: pageIndex)
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: cacheKey)
    }

    nonisolated func image(namespace: String, pageIndex: Int) -> UIImage? {
        entry(namespace: namespace, pageIndex: pageIndex)?.image
    }

    nonisolated func clear() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    @discardableResult
    nonisolated func store(
        _ image: UIImage,
        namespace: String,
        pageIndex: Int,
        pixelSize: Int? = nil
    ) -> Bool {
        let resolvedPixelSize = pixelSize ?? Self.pixelSize(for: image)
        let cacheKey = cacheKey(namespace: namespace, pageIndex: pageIndex)
        let cacheCost = Self.cacheCost(for: image)

        lock.lock()
        if let existing = cache.object(forKey: cacheKey), existing.pixelSize >= resolvedPixelSize {
            lock.unlock()
            return false
        }

        cache.setObject(
            ReaderPagePreviewEntry(image: image, pixelSize: resolvedPixelSize),
            forKey: cacheKey,
            cost: cacheCost
        )
        lock.unlock()

        let userInfo: [AnyHashable: Any] = [
            ReaderPagePreviewNotificationUserInfoKey.namespace: namespace,
            ReaderPagePreviewNotificationUserInfoKey.pageIndex: pageIndex
        ]
        let postUpdate = {
            NotificationCenter.default.post(
                name: .readerPagePreviewDidUpdate,
                object: self,
                userInfo: userInfo
            )
        }

        if Thread.isMainThread {
            postUpdate()
        } else {
            Task { @MainActor in
                postUpdate()
            }
        }

        return true
    }

    nonisolated private func cacheKey(namespace: String, pageIndex: Int) -> NSString {
        "\(namespace)#\(pageIndex)" as NSString
    }

    nonisolated private static func pixelSize(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return max(1, Int(max(width, height).rounded()))
    }

    nonisolated private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}

struct ReaderPageThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let document: ComicDocument
    let pageIndex: Int
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 14
    var style: ReaderPageThumbnailStyle = .browser

    @StateObject private var loader = ReaderPageThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)

            switch loader.phase {
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .idle, .loading:
                ReaderPageThumbnailLoadingPlaceholder(
                    pageIndex: pageIndex,
                    style: style
                )
            case .unavailable:
                ReaderPageThumbnailUnavailablePlaceholder(
                    systemName: placeholderSystemName,
                    pageIndex: pageIndex,
                    style: style
                )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .task(id: loaderRequestID) {
            loader.load(
                document: document,
                pageIndex: pageIndex,
                targetSize: CGSize(width: width, height: height),
                scale: displayScale
            )
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .browser:
            return Color(.secondarySystemBackground)
        case .scrubber:
            return .white.opacity(0.08)
        case .floatingPreview:
            return .white.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch style {
        case .browser:
            return Color.black.opacity(0.08)
        case .scrubber:
            return .white.opacity(0.12)
        case .floatingPreview:
            return .white.opacity(0.16)
        }
    }

    private var placeholderSystemName: String {
        switch document {
        case .pdf:
            return "doc.richtext"
        case .ebook:
            return "book.closed"
        case .imageSequence:
            return "photo"
        case .unsupported:
            return "book.closed"
        }
    }

    private var loaderRequestID: String {
        "\(document.fileURL.path)#\(pageIndex)#\(Int(width))x\(Int(height))@\(Int(displayScale * 100))"
    }
}

private struct ReaderPageThumbnailLoadingPlaceholder: View {
    let pageIndex: Int
    let style: ReaderPageThumbnailStyle

    var body: some View {
        switch style {
        case .browser:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.secondary)

                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .scrubber:
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.9))

                Text("\(pageIndex + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
        case .floatingPreview:
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.95))

                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private struct ReaderPageThumbnailUnavailablePlaceholder: View {
    let systemName: String
    let pageIndex: Int
    let style: ReaderPageThumbnailStyle

    var body: some View {
        switch style {
        case .browser:
            VStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .scrubber:
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text("\(pageIndex + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.54))
            }
        case .floatingPreview:
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))

                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }
}

@MainActor
final class ReaderPageThumbnailLoader: ObservableObject {
    enum Phase {
        case idle
        case loading
        case image(UIImage)
        case unavailable
    }

    @Published private(set) var phase: Phase = .idle
    private var loadTask: Task<Void, Never>?
    private var requestID: String?
    private var previewObserver: NSObjectProtocol?

    func load(document: ComicDocument, pageIndex: Int, targetSize: CGSize, scale: CGFloat) {
        loadTask?.cancel()
        removePreviewObserver()

        let maxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let requestID = "\(document.fileURL.path)#\(pageIndex)#\(maxPixelSize)"
        let requestDidChange = self.requestID != requestID

        self.requestID = requestID

        switch document {
        case .imageSequence(let imageSequence):
            let previewNamespace = ReaderPageCache.namespace(for: imageSequence.url)
            registerPreviewObserver(
                namespace: previewNamespace,
                pageIndex: pageIndex,
                requestID: requestID
            )

            if let previewImage = ReaderPagePreviewStore.shared.image(
                namespace: previewNamespace,
                pageIndex: pageIndex
            ) {
                phase = .image(previewImage)
            } else if requestDidChange || !phase.isImage {
                phase = .loading
            }
        case .pdf, .ebook, .unsupported:
            if requestDidChange || !phase.isImage {
                phase = .loading
            }
        }

        loadTask = Task(priority: .utility) { [weak self] in
            let image: UIImage?

            switch document {
            case .pdf(let pdf):
                image = PDFThumbnailStore.shared.image(
                    for: pdf,
                    pageIndex: pageIndex,
                    maxPixelSize: maxPixelSize
                )
            case .ebook(let ebook):
                image = await LocalEBookThumbnailExtractor.shared.thumbnail(
                    from: ebook.url,
                    maxPixelSize: maxPixelSize
                )
            case .imageSequence(let imageSequence):
                if let pageName = imageSequence.pageName(at: pageIndex) {
                    image = await ReaderImageSequenceThumbnailPipeline.shared.image(
                        documentURL: imageSequence.url,
                        pageSource: imageSequence.pageSource,
                        pageName: pageName,
                        pageIndex: pageIndex,
                        maxPixelSize: maxPixelSize
                    )
                } else {
                    image = nil
                }
            case .unsupported:
                image = nil
            }

            guard let self, !Task.isCancelled, self.requestID == requestID else {
                return
            }

            self.phase = image.map(Phase.image) ?? .unavailable
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        removePreviewObserver()
    }

    deinit {
        loadTask?.cancel()
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
        }
    }

    private func registerPreviewObserver(namespace: String, pageIndex: Int, requestID: String) {
        previewObserver = NotificationCenter.default.addObserver(
            forName: .readerPagePreviewDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = readerPagePreviewUpdateInfo(from: notification)
            Task { @MainActor [weak self, info] in
                guard let self,
                      let info,
                      self.requestID == requestID,
                      info.namespace == namespace,
                      info.pageIndex == pageIndex,
                      let previewImage = ReaderPagePreviewStore.shared.image(
                        namespace: namespace,
                        pageIndex: pageIndex
                      )
                else {
                    return
                }

                self.phase = .image(previewImage)
            }
        }
    }

    private func removePreviewObserver() {
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
            self.previewObserver = nil
        }
    }
}

private extension ReaderPageThumbnailLoader.Phase {
    var isImage: Bool {
        if case .image = self {
            return true
        }

        return false
    }
}

@MainActor
final class PDFThumbnailStore {
    static let shared = PDFThumbnailStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func image(for document: PDFComicDocument, pageIndex: Int, maxPixelSize: Int) -> UIImage? {
        let cacheKey = cacheKey(for: document, pageIndex: pageIndex, maxPixelSize: maxPixelSize)
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            return cachedImage
        }

        guard let page = document.pdfDocument.page(at: pageIndex) else {
            return nil
        }

        let thumbnailSize = CGSize(
            width: CGFloat(maxPixelSize),
            height: CGFloat(maxPixelSize) * 1.45
        )
        let image = page.thumbnail(of: thumbnailSize, for: .mediaBox)
        cache.setObject(image, forKey: nsCacheKey, cost: Self.cacheCost(for: image))
        return image
    }

    private func cacheKey(for document: PDFComicDocument, pageIndex: Int, maxPixelSize: Int) -> String {
        let resourceValues = try? document.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationTime = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = resourceValues?.fileSize ?? 0
        return "\(document.url.path)#\(fileSize)#\(Int(modificationTime))#\(pageIndex)#\(maxPixelSize)"
    }

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

actor ReaderImageSequenceThumbnailPipeline {
    static let shared = ReaderImageSequenceThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func image(
        documentURL: URL,
        pageSource: any ComicPageDataSource,
        pageName: String,
        pageIndex: Int,
        maxPixelSize: Int
    ) async -> UIImage? {
        let namespace = ReaderPageCache.namespace(for: documentURL)
        let cacheKey = "\(namespace)#\(pageIndex)#\(pageName)#\(maxPixelSize)"
        let nsCacheKey = cacheKey as NSString

        if let cachedImage = cache.object(forKey: nsCacheKey) {
            return cachedImage
        }

        if let previewEntry = ReaderPagePreviewStore.shared.entry(
            namespace: namespace,
            pageIndex: pageIndex
        ), previewEntry.pixelSize >= maxPixelSize {
            cache.setObject(
                previewEntry.image,
                forKey: nsCacheKey,
                cost: Self.cacheCost(for: previewEntry.image)
            )
            return previewEntry.image
        }

        if let inFlightTask = inFlightTasks[cacheKey] {
            return await inFlightTask.value
        }

        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let pageData = try? await pageSource.dataForPage(at: pageIndex) else {
                return nil
            }

            return Self.loadDownsampledImage(from: pageData, maxPixelSize: maxPixelSize)
        }
        inFlightTasks[cacheKey] = task

        let image = await task.value
        inFlightTasks[cacheKey] = nil

        if let image {
            cache.setObject(image, forKey: nsCacheKey, cost: Self.cacheCost(for: image))
            ReaderPagePreviewStore.shared.store(
                image,
                namespace: namespace,
                pageIndex: pageIndex
            )
        }

        return image
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
        inFlightTasks.values.forEach { $0.cancel() }
        inFlightTasks.removeAll()
    }

    private static func loadDownsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
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

        return UIImage(data: data)
    }

    private static func cacheCost(for image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}
