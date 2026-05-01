import Foundation
import PDFKit

enum ComicDocumentLoadError: LocalizedError {
    case fileMissing
    case unreadablePDF
    case unsupportedRemoteStreamingFormat(String)

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            return "The selected comic file could not be found."
        case .unreadablePDF:
            return "The PDF could not be opened."
        case .unsupportedRemoteStreamingFormat(let fileName):
            return "\(fileName) still needs a full download before it can be opened."
        }
    }
}

nonisolated final class ComicDocumentLoader {
    private let fileManager: FileManager
    private let directoryImageSequenceReader: DirectoryImageSequenceReader
    private let libArchiveReader: LibArchiveReader
    private let zipArchiveReader: ZIPArchiveReader
    private let tarArchiveReader: TARArchiveReader
    private let remoteZIPArchiveReader: RemoteZIPArchiveReader

    init(
        fileManager: FileManager = .default,
        directoryImageSequenceReader: DirectoryImageSequenceReader = DirectoryImageSequenceReader(),
        libArchiveReader: LibArchiveReader = LibArchiveReader(),
        zipArchiveReader: ZIPArchiveReader = ZIPArchiveReader(),
        tarArchiveReader: TARArchiveReader = TARArchiveReader(),
        remoteZIPArchiveReader: RemoteZIPArchiveReader = RemoteZIPArchiveReader()
    ) {
        self.fileManager = fileManager
        self.directoryImageSequenceReader = directoryImageSequenceReader
        self.libArchiveReader = libArchiveReader
        self.zipArchiveReader = zipArchiveReader
        self.tarArchiveReader = tarArchiveReader
        self.remoteZIPArchiveReader = remoteZIPArchiveReader
    }

    func loadDocument(for comic: LibraryComic, sourceRootURL: URL) throws -> ComicDocument {
        let fileURL = resolveFileURL(for: comic, sourceRootURL: sourceRootURL)
        return try loadDocument(at: fileURL)
    }

    func loadDocument(at fileURL: URL) throws -> ComicDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ComicDocumentLoadError.fileMissing
        }

        if isDirectory(fileURL) {
            return .imageSequence(try directoryImageSequenceReader.loadDocument(at: fileURL))
        }

        let `extension` = fileURL.pathExtension.lowercased()
        switch `extension` {
        case "pdf":
            guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else {
                throw ComicDocumentLoadError.unreadablePDF
            }

            return .pdf(
                PDFComicDocument(
                    url: fileURL,
                    pdfDocument: document
                )
            )
        case "cbz", "zip":
            return .imageSequence(try zipArchiveReader.loadDocument(at: fileURL))
        case "cbr", "rar", "cb7", "7z", "arj":
            return .imageSequence(try libArchiveReader.loadDocument(at: fileURL))
        case "cbt", "tar":
            return .imageSequence(try tarArchiveReader.loadDocument(at: fileURL))
        case "epub":
            return .ebook(
                EBookComicDocument(
                    url: fileURL,
                    fileExtension: `extension`,
                    readerKind: .epubJS,
                    documentID: EBookDocumentSupport.documentIdentifier(for: fileURL)
                )
            )
        case "mobi":
            if EBookDocumentSupport.canPreviewDocument(at: fileURL) {
                return .ebook(
                    EBookComicDocument(
                        url: fileURL,
                        fileExtension: `extension`,
                        readerKind: .quickLook,
                        documentID: EBookDocumentSupport.documentIdentifier(for: fileURL)
                    )
                )
            }

            return .unsupported(
                UnsupportedComicDocument(
                    url: fileURL,
                    fileExtension: `extension`,
                    reason: EBookDocumentSupport.unsupportedReason(for: fileURL)
                )
            )
        default:
            return .unsupported(
                UnsupportedComicDocument(
                    url: fileURL,
                    fileExtension: `extension`,
                    reason: "Archive and image-stream readers are the next migration step."
                )
            )
        }
    }

    func supportsRemoteStreaming(for fileName: String) -> Bool {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "cbz", "zip":
            return true
        default:
            return false
        }
    }

    func loadRemoteDocument(
        named fileName: String,
        documentURL: URL,
        reader: any RemoteRandomAccessFileReader
    ) async throws -> ComicDocument {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "cbz", "zip":
            return .imageSequence(
                try await remoteZIPArchiveReader.loadDocument(
                    from: reader,
                    documentURL: documentURL
                )
            )
        default:
            throw ComicDocumentLoadError.unsupportedRemoteStreamingFormat(fileName)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func resolveFileURL(for comic: LibraryComic, sourceRootURL: URL) -> URL {
        let relativePath = {
            let rawPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawPath.isEmpty {
                return comic.fileName
            }

            return rawPath
        }()

        if relativePath.hasPrefix("/") {
            return sourceRootURL.appendingPathComponent(String(relativePath.dropFirst()))
        }

        return sourceRootURL.appendingPathComponent(relativePath)
    }
}
