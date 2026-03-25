import Combine
import ImageIO
import PDFKit
import SwiftUI
import UIKit

struct ReaderThumbnailBrowserSheet: View {
    let document: ComicDocument
    let currentPageIndex: Int
    let onSelectPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isPageNumberFieldFocused: Bool
    @State private var pageNumberText = ""

    private let thumbnailWidth: CGFloat = 118
    private let thumbnailHeight: CGFloat = 166

    private var pageCount: Int {
        document.pageCount ?? 0
    }

    private var normalizedSelectedPageIndex: Int? {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...pageCount).contains(pageNumber)
        else {
            return nil
        }

        return pageNumber - 1
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            pageOverviewCard(proxy: proxy)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth), spacing: 16)],
                                spacing: 18
                            ) {
                                ForEach(0..<pageCount, id: \.self) { pageIndex in
                                    ReaderThumbnailCell(
                                        document: document,
                                        pageIndex: pageIndex,
                                        isCurrentPage: pageIndex == currentPageIndex,
                                        width: thumbnailWidth,
                                        height: thumbnailHeight
                                    ) {
                                        openPage(at: pageIndex)
                                    }
                                    .id(pageIndex)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
                .navigationTitle("Pages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Current") {
                            isPageNumberFieldFocused = false
                            scrollToPage(currentPageIndex, using: proxy, animated: true)
                        }
                    }
                }
                .onAppear {
                    if pageNumberText.isEmpty {
                        pageNumberText = "\(currentPageIndex + 1)"
                    }
                }
                .onChange(of: currentPageIndex) { _, newValue in
                    guard !isPageNumberFieldFocused else {
                        return
                    }

                    pageNumberText = "\(newValue + 1)"
                }
                .task(id: scrollRequestID) {
                    guard pageCount > 0 else {
                        return
                    }

                    try? await Task.sleep(nanoseconds: 120_000_000)
                    scrollToPage(currentPageIndex, using: proxy, animated: false)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var scrollRequestID: String {
        "\(document.fileURL.path)#\(currentPageIndex)#\(pageCount)"
    }

    private func pageOverviewCard(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Browse Pages")
                    .font(.title3.weight(.semibold))

                Text("Jump quickly, compare nearby pages, or return to where you left off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ReaderThumbnailStatChip(
                    title: "Current",
                    value: "\(currentPageIndex + 1)"
                )

                ReaderThumbnailStatChip(
                    title: "Total",
                    value: "\(pageCount)"
                )
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open page")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Page", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPageNumberFieldFocused)
                        .submitLabel(.go)
                        .frame(maxWidth: 132)
                        .onSubmit {
                            openSelectedPage()
                        }
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Open") {
                        openSelectedPage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedSelectedPageIndex == nil)

                    Button("Current") {
                        isPageNumberFieldFocused = false
                        scrollToPage(currentPageIndex, using: proxy, animated: true)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func openSelectedPage() {
        guard let pageIndex = normalizedSelectedPageIndex else {
            return
        }

        openPage(at: pageIndex)
    }

    private func openPage(at pageIndex: Int) {
        onSelectPage(pageIndex)
        dismiss()
    }

    private func scrollToPage(_ pageIndex: Int, using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(pageIndex, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2), action)
        } else {
            action()
        }
    }
}

private struct ReaderThumbnailCell: View {
    let document: ComicDocument
    let pageIndex: Int
    let isCurrentPage: Bool
    let width: CGFloat
    let height: CGFloat
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ReaderPageThumbnailView(
                    document: document,
                    pageIndex: pageIndex,
                    width: width,
                    height: height
                )

                Text("Page \(pageIndex + 1)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isCurrentPage ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if isCurrentPage {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(width: width + 20, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isCurrentPage ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isCurrentPage ? Color.accentColor : Color.black.opacity(0.08),
                        lineWidth: isCurrentPage ? 2 : 1
                    )
            }
            .shadow(
                color: isCurrentPage ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.04),
                radius: 10,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderThumbnailStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.66))
        )
    }
}

private struct ReaderPageThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let document: ComicDocument
    let pageIndex: Int
    let width: CGFloat
    let height: CGFloat

    @StateObject private var loader = ReaderPageThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: placeholderSystemName)
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("\(pageIndex + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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

    private var placeholderSystemName: String {
        switch document {
        case .pdf:
            return "doc.richtext"
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

@MainActor
private final class ReaderPageThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var loadTask: Task<Void, Never>?
    private var requestID: String?

    func load(document: ComicDocument, pageIndex: Int, targetSize: CGSize, scale: CGFloat) {
        loadTask?.cancel()

        let maxPixelSize = Int(max(targetSize.width, targetSize.height) * max(scale, 1))
        let requestID = "\(document.fileURL.path)#\(pageIndex)#\(maxPixelSize)"

        if self.requestID != requestID {
            image = nil
        }

        self.requestID = requestID
        loadTask = Task { [weak self] in
            let image: UIImage?

            switch document {
            case .pdf(let pdf):
                image = PDFThumbnailStore.shared.image(
                    for: pdf,
                    pageIndex: pageIndex,
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
private final class PDFThumbnailStore {
    static let shared = PDFThumbnailStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 64 * 1_024 * 1_024
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
}

private actor ReaderImageSequenceThumbnailPipeline {
    static let shared = ReaderImageSequenceThumbnailPipeline()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1_024 * 1_024
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
        }

        return image
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
