import Foundation
import ImageIO
import PDFKit
import UIKit

struct ExtractedComicMetadata {
    let pageCount: Int
    let originalCoverSize: CGSize?
    let coverImage: UIImage?
    let importedComicInfo: ImportedComicInfoMetadata?

    var coverSizeRatio: Double? {
        guard let originalCoverSize, originalCoverSize.height > 0 else {
            return nil
        }

        return originalCoverSize.width / originalCoverSize.height
    }

    var originalCoverSizeString: String? {
        guard let originalCoverSize else {
            return nil
        }

        let width = Int(originalCoverSize.width.rounded())
        let height = Int(originalCoverSize.height.rounded())
        guard width > 0, height > 0 else {
            return nil
        }

        return "\(width)x\(height)"
    }
}

final class LibraryComicMetadataExtractor {
    private let libArchiveReader: LibArchiveReader
    private let zipArchiveReader: ZIPArchiveReader
    private let tarArchiveReader: TARArchiveReader
    private let directoryImageSequenceInspector: DirectoryImageSequenceInspector
    private let comicInfoXMLParser: ComicInfoXMLParser
    private let fileManager: FileManager

    init(
        libArchiveReader: LibArchiveReader = LibArchiveReader(),
        zipArchiveReader: ZIPArchiveReader = ZIPArchiveReader(),
        tarArchiveReader: TARArchiveReader = TARArchiveReader(),
        directoryImageSequenceInspector: DirectoryImageSequenceInspector = DirectoryImageSequenceInspector(),
        comicInfoXMLParser: ComicInfoXMLParser = ComicInfoXMLParser(),
        fileManager: FileManager = .default
    ) {
        self.libArchiveReader = libArchiveReader
        self.zipArchiveReader = zipArchiveReader
        self.tarArchiveReader = tarArchiveReader
        self.directoryImageSequenceInspector = directoryImageSequenceInspector
        self.comicInfoXMLParser = comicInfoXMLParser
        self.fileManager = fileManager
    }

    func extractMetadata(for fileURL: URL, coverPage: Int = 1) throws -> ExtractedComicMetadata? {
        if isDirectory(fileURL),
           let inspection = try directoryImageSequenceInspector.inspectComicDirectory(at: fileURL) {
            return try extractDirectoryMetadata(for: inspection, coverPage: coverPage)
        }

        let fileExtension = fileURL.pathExtension.lowercased()

        switch fileExtension {
        case "pdf":
            return try extractPDFMetadata(for: fileURL, coverPage: coverPage)
        case "cbz", "zip":
            return try extractArchiveMetadata(
                zipArchiveReader.extractMetadata(at: fileURL, coverPage: coverPage)
            )
        case "cbr", "rar", "cb7", "7z", "arj":
            return try extractArchiveMetadata(
                libArchiveReader.extractMetadata(at: fileURL, coverPage: coverPage)
            )
        case "cbt", "tar":
            return try extractArchiveMetadata(
                tarArchiveReader.extractMetadata(at: fileURL, coverPage: coverPage)
            )
        case "epub", "mobi":
            return try extractEBookMetadata(for: fileURL)
        default:
            return nil
        }
    }

    /// Lightweight extraction: only page count, no cover image or ComicInfo.xml.
    /// Much faster for initial library import since it avoids decompressing image data.
    func extractPageCountOnly(for fileURL: URL) -> Int? {
        if isDirectory(fileURL) {
            if let inspection = try? directoryImageSequenceInspector.inspectComicDirectory(at: fileURL) {
                return inspection.pageFiles.count
            }
        }

        let fileExtension = fileURL.pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return PDFDocument(url: fileURL)?.pageCount
        case "cbz", "zip":
            return (try? zipArchiveReader.countPages(at: fileURL)) ?? (try? libArchiveReader.countPages(at: fileURL))
        case "cbr", "rar", "cb7", "7z", "arj":
            return try? libArchiveReader.countPages(at: fileURL)
        case "cbt", "tar":
            return try? tarArchiveReader.countPages(at: fileURL)
        case "epub", "mobi":
            return 0
        default:
            return nil
        }
    }

    private func extractEBookMetadata(for fileURL: URL) throws -> ExtractedComicMetadata? {
        let coverImage = autoreleasepool {
            EBookDocumentSupport.generateThumbnail(at: fileURL, maxPixelSize: 1400)
        }

        return ExtractedComicMetadata(
            pageCount: 0,
            originalCoverSize: coverImage?.size,
            coverImage: coverImage,
            importedComicInfo: nil
        )
    }

    private func extractDirectoryMetadata(
        for inspection: DirectoryImageSequenceInspection,
        coverPage: Int
    ) throws -> ExtractedComicMetadata? {
        guard !inspection.pageFiles.isEmpty else {
            return nil
        }

        let coverIndex = min(max(coverPage - 1, 0), inspection.pageFiles.count - 1)
        let coverData = try Data(contentsOf: inspection.pageFiles[coverIndex], options: [.mappedIfSafe])
        let coverImage = UIImage(data: coverData)
        let originalCoverSize = imagePixelSize(from: coverData) ?? coverImage?.size
        let importedComicInfo = try inspection.comicInfoURL.flatMap { comicInfoURL in
            let xmlData = try Data(contentsOf: comicInfoURL, options: [.mappedIfSafe])
            return comicInfoXMLParser.parse(xmlData)
        }

        return ExtractedComicMetadata(
            pageCount: inspection.pageFiles.count,
            originalCoverSize: originalCoverSize,
            coverImage: coverImage,
            importedComicInfo: importedComicInfo
        )
    }

    func saveCover(_ image: UIImage, to coverURL: URL) throws {
        let parentURL = coverURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let originalSize = image.size
        let aspectRatio = max(originalSize.width / max(originalSize.height, 1), 0.0001)
        let targetSize: CGSize

        if originalSize.width > originalSize.height {
            targetSize = CGSize(width: 640, height: 640 / aspectRatio)
        } else if aspectRatio < 0.5 {
            targetSize = CGSize(width: 960 * aspectRatio, height: 960)
        } else {
            targetSize = CGSize(width: 480, height: 480 / aspectRatio)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let scaledImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = scaledImage.jpegData(compressionQuality: 0.75) else {
            throw LibraryScannerError.scanFailed("Unable to encode cover image.")
        }

        try data.write(to: coverURL, options: [.atomic])
    }

    private func extractPDFMetadata(for fileURL: URL, coverPage: Int) throws -> ExtractedComicMetadata? {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
            return nil
        }

        let pageIndex = min(max(coverPage - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: pageIndex) else {
            return ExtractedComicMetadata(
                pageCount: document.pageCount,
                originalCoverSize: nil,
                coverImage: nil,
                importedComicInfo: nil
            )
        }

        let originalSize = page.bounds(for: .mediaBox).size
        let thumbnail = page.thumbnail(of: CGSize(width: 1400, height: 1400), for: .mediaBox)

        return ExtractedComicMetadata(
            pageCount: document.pageCount,
            originalCoverSize: originalSize.width > 0 && originalSize.height > 0 ? originalSize : nil,
            coverImage: thumbnail.size.width > 0 && thumbnail.size.height > 0 ? thumbnail : nil,
            importedComicInfo: nil
        )
    }

    private func extractArchiveMetadata(_ archiveMetadata: @autoclosure () throws -> ArchiveImageMetadata) throws -> ExtractedComicMetadata? {
        let archiveMetadata = try archiveMetadata()
        let coverImage = archiveMetadata.coverData.flatMap { UIImage(data: $0) }
        let originalCoverSize = archiveMetadata.coverData.flatMap(imagePixelSize(from:))
        let importedComicInfo = archiveMetadata.embeddedComicInfoData.flatMap { xmlData in
            comicInfoXMLParser.parse(xmlData)
        }

        return ExtractedComicMetadata(
            pageCount: archiveMetadata.pageCount,
            originalCoverSize: originalCoverSize ?? coverImage?.size,
            coverImage: coverImage,
            importedComicInfo: importedComicInfo
        )
    }

    private func imagePixelSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              pixelWidth > 0,
              pixelHeight > 0
        else {
            return nil
        }

        return CGSize(width: pixelWidth, height: pixelHeight)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
