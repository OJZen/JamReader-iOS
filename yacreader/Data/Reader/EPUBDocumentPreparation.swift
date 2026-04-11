import Foundation

struct EPUBPreparedDocument: Equatable {
    let documentID: String
    let readerHTMLURL: URL
    let readAccessRootURL: URL
    let packageRelativePath: String
}

enum EPUBDocumentPreparationError: LocalizedError {
    case missingReaderAssets
    case invalidArchiveEntry(String)
    case missingContainerXML
    case invalidContainerXML
    case missingPackageDocument(String)

    var errorDescription: String? {
        switch self {
        case .missingReaderAssets:
            return "The EPUB reader assets are missing from the app bundle."
        case .invalidArchiveEntry(let path):
            return "The EPUB contains an invalid entry path: \(path)"
        case .missingContainerXML:
            return "The EPUB is missing META-INF/container.xml."
        case .invalidContainerXML:
            return "The EPUB container metadata could not be parsed."
        case .missingPackageDocument(let path):
            return "The EPUB package document could not be found at \(path)."
        }
    }
}

actor EPUBDocumentPreparationService {
    static let shared = EPUBDocumentPreparationService()

    private let fileManager: FileManager
    private let assetDirectoryName = "SharedAssets"
    private let booksDirectoryName = "Books"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepare(document: EBookComicDocument) async throws -> EPUBPreparedDocument {
        let rootURL = try preparationRootURL()
        try ensureSharedAssets(in: rootURL)

        let bookRootURL = try ensureBookExtraction(for: document, in: rootURL)
        let packageDocumentURL = try await locatePackageDocument(in: bookRootURL)
        let readerHTMLURL = rootURL
            .appendingPathComponent(assetDirectoryName, isDirectory: true)
            .appendingPathComponent("reader.html", isDirectory: false)
        let packageRelativePath = relativePath(
            from: readerHTMLURL.deletingLastPathComponent(),
            to: packageDocumentURL
        )

        return EPUBPreparedDocument(
            documentID: document.documentID,
            readerHTMLURL: readerHTMLURL,
            readAccessRootURL: rootURL,
            packageRelativePath: packageRelativePath
        )
    }

    private func preparationRootURL() throws -> URL {
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = cachesURL.appendingPathComponent("EPUBReader", isDirectory: true)
        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return rootURL
    }

    private func ensureSharedAssets(in rootURL: URL) throws {
        let assetRootURL = rootURL.appendingPathComponent(assetDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: assetRootURL.path) {
            try fileManager.createDirectory(at: assetRootURL, withIntermediateDirectories: true)
        }

        try copyBundledAsset(
            named: "reader",
            extension: "html",
            to: assetRootURL.appendingPathComponent("reader.html", isDirectory: false)
        )
        try copyBundledAsset(
            named: "epub.min",
            extension: "js",
            to: assetRootURL.appendingPathComponent("epub.min.js", isDirectory: false)
        )
    }

    private func ensureBookExtraction(
        for document: EBookComicDocument,
        in rootURL: URL
    ) throws -> URL {
        let documentRootURL = rootURL
            .appendingPathComponent(booksDirectoryName, isDirectory: true)
            .appendingPathComponent(document.documentID, isDirectory: true)
        let bookRootURL = documentRootURL.appendingPathComponent("book", isDirectory: true)

        if fileManager.fileExists(atPath: bookRootURL.path) {
            let containerURL = bookRootURL
                .appendingPathComponent("META-INF", isDirectory: true)
                .appendingPathComponent("container.xml", isDirectory: false)
            if fileManager.fileExists(atPath: containerURL.path) {
                return bookRootURL
            }

            try? fileManager.removeItem(at: documentRootURL)
        }

        try fileManager.createDirectory(at: bookRootURL, withIntermediateDirectories: true)
        try extractEPUB(from: document.url, into: bookRootURL)
        return bookRootURL
    }

    private func extractEPUB(from sourceURL: URL, into destinationURL: URL) throws {
        let archiveReader = try YRLibArchiveReader(archiveURL: sourceURL)

        for (index, entryPath) in archiveReader.entryPaths.enumerated() {
            let destinationFileURL = try destinationURLForArchiveEntry(
                entryPath,
                in: destinationURL
            )
            try fileManager.createDirectory(
                at: destinationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let entryData = try archiveReader.dataForEntry(at: index)
            try entryData.write(to: destinationFileURL, options: .atomic)
        }
    }

    private func locatePackageDocument(in extractedBookRootURL: URL) async throws -> URL {
        let containerURL = extractedBookRootURL
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml", isDirectory: false)
        guard fileManager.fileExists(atPath: containerURL.path) else {
            throw EPUBDocumentPreparationError.missingContainerXML
        }

        let containerData = try Data(contentsOf: containerURL)
        let rootfilePath = await MainActor.run { () -> String? in
            let xml = XMLHash.config { options in
                options.shouldProcessNamespaces = true
                options.detectParsingErrors = true
            }.parse(containerData)

            return xml["container"]["rootfiles"]["rootfile"]
                .all
                .compactMap { $0.element?.attribute(by: "full-path")?.text }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        guard let rootfilePath else {
            throw EPUBDocumentPreparationError.invalidContainerXML
        }

        let packageURL = try destinationURLForArchiveEntry(rootfilePath, in: extractedBookRootURL)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw EPUBDocumentPreparationError.missingPackageDocument(rootfilePath)
        }

        return packageURL
    }

    private func copyBundledAsset(
        named name: String,
        extension ext: String,
        to destinationURL: URL
    ) throws {
        guard let sourceURL = bundledAssetURL(named: name, extension: ext) else {
            throw EPUBDocumentPreparationError.missingReaderAssets
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            let sourceData = try Data(contentsOf: sourceURL)
            let destinationData = try Data(contentsOf: destinationURL)
            if sourceData == destinationData {
                return
            }

            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func bundledAssetURL(named name: String, extension ext: String) -> URL? {
        let fileName = "\(name).\(ext)"
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/EPUBReader"),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "EPUBReader"),
            Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Resources/EPUBReader"),
            Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "EPUBReader")
        ]

        if let directMatch = candidates.compactMap({ $0 }).first {
            return directMatch
        }

        return Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?
            .first { $0.lastPathComponent == fileName }
    }

    private func destinationURLForArchiveEntry(
        _ entryPath: String,
        in rootURL: URL
    ) throws -> URL {
        let normalizedPath = entryPath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let components = normalizedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !components.isEmpty, !components.contains("..") else {
            throw EPUBDocumentPreparationError.invalidArchiveEntry(entryPath)
        }

        return components.reduce(rootURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func relativePath(from baseDirectoryURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseDirectoryURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents

        var commonIndex = 0
        while commonIndex < min(baseComponents.count, targetComponents.count),
              baseComponents[commonIndex] == targetComponents[commonIndex] {
            commonIndex += 1
        }

        let parentComponents = Array(repeating: "..", count: max(baseComponents.count - commonIndex, 0))
        let childComponents = Array(targetComponents.dropFirst(commonIndex))
        return (parentComponents + childComponents).joined(separator: "/")
    }
}
