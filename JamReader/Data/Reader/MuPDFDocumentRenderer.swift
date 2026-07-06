import Foundation
import UIKit

enum MuPDFDocumentRendererError: LocalizedError {
    case unavailable
    case unsupportedFormat(String)
    case openFailed(String)
    case renderFailed(String)
    case invalidPage(Int)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "MuPDF is not linked into this build."
        case .unsupportedFormat(let fileExtension):
            return "\(fileExtension.uppercased()) is not configured for MuPDF rendering."
        case .openFailed(let message):
            return message
        case .renderFailed(let message):
            return message
        case .invalidPage(let pageIndex):
            return "Page \(pageIndex + 1) is not available."
        case .imageEncodingFailed:
            return "The rendered page could not be encoded."
        }
    }
}

nonisolated final class MuPDFDocumentRenderer: @unchecked Sendable {
    nonisolated static let supportedExtensions: Set<String> = ["pdf", "epub"]

    nonisolated static var isAvailable: Bool {
        YRMuPDFDocument.isAvailable()
    }

    nonisolated static func supportsFileExtension(_ fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }

    nonisolated static func canAttemptDocumentOpen(at fileURL: URL) -> Bool {
        isAvailable && supportsFileExtension(fileURL.pathExtension)
    }

    nonisolated static func unsupportedReason(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension.uppercased()
        if isAvailable {
            return "\(fileExtension) could not be opened by MuPDF."
        }
        return "\(fileExtension) reading requires the MuPDF engine, which is not linked into this build."
    }

    let url: URL
    let pageCount: Int

    private let document: YRMuPDFDocument

    init(url: URL) throws {
        guard Self.supportsFileExtension(url.pathExtension) else {
            throw MuPDFDocumentRendererError.unsupportedFormat(url.pathExtension)
        }

        guard Self.isAvailable else {
            throw MuPDFDocumentRendererError.unavailable
        }

        let document: YRMuPDFDocument
        do {
            document = try YRMuPDFDocument(url: url)
        } catch {
            throw MuPDFDocumentRendererError.openFailed(
                error.localizedDescription
            )
        }

        self.url = url
        self.document = document
        self.pageCount = max(document.pageCount, 0)
    }

    func imageForPage(at pageIndex: Int, maxPixelSize: Int) throws -> UIImage {
        guard (0..<pageCount).contains(pageIndex) else {
            throw MuPDFDocumentRendererError.invalidPage(pageIndex)
        }

        do {
            return try document.renderPage(
                at: pageIndex,
                maxPixelSize: max(maxPixelSize, 1)
            )
        } catch {
            throw MuPDFDocumentRendererError.renderFailed(
                error.localizedDescription
            )
        }
    }

    func imageDataForPage(at pageIndex: Int, maxPixelSize: Int) throws -> Data {
        let image = try imageForPage(at: pageIndex, maxPixelSize: maxPixelSize)
        guard let data = image.pngData() else {
            throw MuPDFDocumentRendererError.imageEncodingFailed
        }
        return data
    }
}

nonisolated final class MuPDFComicDocumentReader {
    private let pageRenderPixelSize: Int

    init(pageRenderPixelSize: Int = 2600) {
        self.pageRenderPixelSize = pageRenderPixelSize
    }

    func loadDocument(at fileURL: URL) throws -> ImageSequenceComicDocument {
        let renderer = try MuPDFDocumentRenderer(url: fileURL)
        guard renderer.pageCount > 0 else {
            throw MuPDFDocumentRendererError.openFailed("MuPDF found no readable pages in this document.")
        }

        return ImageSequenceComicDocument(
            url: fileURL,
            pageNames: (0..<renderer.pageCount).map { "Page \($0 + 1)" },
            pageSource: MuPDFPageSource(
                renderer: renderer,
                pageRenderPixelSize: pageRenderPixelSize
            ),
            kind: .renderedDocument
        )
    }
}

actor MuPDFPageSource: ComicPageDataSource {
    private var renderer: MuPDFDocumentRenderer?
    private let pageRenderPixelSize: Int
    private let sharedCache = ReaderPageCache.shared
    private let cacheNamespace: String
    private let cache: NSCache<NSNumber, NSData> = {
        let cache = NSCache<NSNumber, NSData>()
        cache.countLimit = 8
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    init(renderer: MuPDFDocumentRenderer, pageRenderPixelSize: Int) {
        self.renderer = renderer
        self.pageRenderPixelSize = pageRenderPixelSize
        self.cacheNamespace = ReaderPageCache.namespace(for: renderer.url)
    }

    func dataForPage(at index: Int) async throws -> Data {
        guard let renderer else {
            throw MuPDFDocumentRendererError.openFailed("The MuPDF document has already been closed.")
        }

        if let cachedValue = cache.object(forKey: NSNumber(value: index)) {
            return Data(referencing: cachedValue)
        }

        let cacheKey = ReaderPageCacheKey(
            namespace: cacheNamespace,
            pageIdentifier: "mupdf-\(index)-\(pageRenderPixelSize)"
        )
        if let cachedPage = await sharedCache.data(for: cacheKey) {
            cache.setObject(cachedPage as NSData, forKey: NSNumber(value: index), cost: cachedPage.count)
            return cachedPage
        }

        let pageData = try renderer.imageDataForPage(
            at: index,
            maxPixelSize: pageRenderPixelSize
        )
        cache.setObject(pageData as NSData, forKey: NSNumber(value: index), cost: pageData.count)
        await sharedCache.store(pageData, for: cacheKey)
        return pageData
    }

    func prefetchPages(at indices: [Int]) async {
        for index in indices {
            _ = try? await dataForPage(at: index)
        }
    }

    func close() async {
        renderer = nil
        cache.removeAllObjects()
    }
}

enum MuPDFThumbnailRenderer {
    nonisolated static func thumbnail(
        from fileURL: URL,
        pageIndex: Int = 0,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let renderer = try? MuPDFDocumentRenderer(url: fileURL) else {
            return nil
        }
        guard renderer.pageCount > 0 else {
            return nil
        }

        return try? renderer.imageForPage(
            at: min(max(pageIndex, 0), max(renderer.pageCount - 1, 0)),
            maxPixelSize: maxPixelSize
        )
    }

    nonisolated static func pageCount(for fileURL: URL) -> Int? {
        guard let renderer = try? MuPDFDocumentRenderer(url: fileURL) else {
            return nil
        }
        return renderer.pageCount
    }
}
