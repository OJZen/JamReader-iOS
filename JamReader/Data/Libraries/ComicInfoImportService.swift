import Foundation

struct ComicInfoImportBatchResult: Equatable {
    let totalCount: Int
    let importedCount: Int
    let skippedCount: Int
    let failedTitles: [String]

    var failedCount: Int {
        failedTitles.count
    }

    var alertTitle: String {
        if importedCount > 0 && failedCount == 0 {
            return "ComicInfo Imported"
        }

        if importedCount == 0 && skippedCount > 0 && failedCount == 0 {
            return "No ComicInfo Found"
        }

        return "ComicInfo Import Finished"
    }

    var alertMessage: String {
        var lines = [
            "\(importedCount) imported",
            "\(skippedCount) skipped",
            "\(failedCount) failed"
        ]

        if !failedTitles.isEmpty {
            let preview = failedTitles.prefix(5).joined(separator: "\n")
            lines.append("Failed comics:\n\(preview)")
        }

        return lines.joined(separator: "\n")
    }
}

final class ComicInfoImportService {
    private let storageManager: LibraryStorageManager
    private let databaseWriter: LibraryDatabaseWriter
    private let metadataExtractor: LibraryComicMetadataExtractor

    init(
        storageManager: LibraryStorageManager,
        databaseWriter: LibraryDatabaseWriter,
        metadataExtractor: LibraryComicMetadataExtractor = LibraryComicMetadataExtractor()
    ) {
        self.storageManager = storageManager
        self.databaseWriter = databaseWriter
        self.metadataExtractor = metadataExtractor
    }

    func importEmbeddedComicInfo(
        for descriptor: LibraryDescriptor,
        comics: [LibraryComic],
        policy: ComicInfoImportPolicy = .overwriteExisting,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) async throws -> ComicInfoImportBatchResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.importEmbeddedComicInfoSynchronously(
                        for: descriptor,
                        comics: comics,
                        policy: policy,
                        progressHandler: progressHandler
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadEmbeddedComicInfo(
        for descriptor: LibraryDescriptor,
        comic: LibraryComic
    ) async throws -> ImportedComicInfoMetadata? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let metadata = try self.loadEmbeddedComicInfoSynchronously(
                        for: descriptor,
                        comic: comic
                    )
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func importEmbeddedComicInfoSynchronously(
        for descriptor: LibraryDescriptor,
        comics: [LibraryComic],
        policy: ComicInfoImportPolicy,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> ComicInfoImportBatchResult {
        let uniqueComics = uniqueComicsPreservingOrder(comics)
        guard !uniqueComics.isEmpty else {
            return ComicInfoImportBatchResult(
                totalCount: 0,
                importedCount: 0,
                skippedCount: 0,
                failedTitles: []
            )
        }

        let databaseURL = storageManager.databaseURL(for: descriptor)
        var importedCount = 0
        var skippedCount = 0
        var failedTitles: [String] = []

        try storageManager.withScopedSourceAccess(for: descriptor) { session in
            for (index, comic) in uniqueComics.enumerated() {
                progressHandler?(
                    LibraryScanProgress(
                        phase: .importingMetadata,
                        currentPath: progressPath(for: comic),
                        processedFolderCount: 0,
                        processedComicCount: index + 1
                    )
                )

                do {
                    let fileURL = resolveFileURL(for: comic, sourceRootURL: session.sourceURL)
                    guard let extractedMetadata = try metadataExtractor.extractMetadata(for: fileURL),
                          let importedComicInfo = extractedMetadata.importedComicInfo
                    else {
                        skippedCount += 1
                        continue
                    }

                    try databaseWriter.applyImportedComicInfo(
                        importedComicInfo,
                        for: comic.id,
                        in: databaseURL,
                        policy: policy
                    )
                    importedCount += 1
                } catch {
                    failedTitles.append(comic.displayTitle)
                }
            }
        }

        progressHandler?(
            LibraryScanProgress(
                phase: .finalizing,
                currentPath: nil,
                processedFolderCount: 0,
                processedComicCount: uniqueComics.count
            )
        )

        return ComicInfoImportBatchResult(
            totalCount: uniqueComics.count,
            importedCount: importedCount,
            skippedCount: skippedCount,
            failedTitles: failedTitles
        )
    }

    private func loadEmbeddedComicInfoSynchronously(
        for descriptor: LibraryDescriptor,
        comic: LibraryComic
    ) throws -> ImportedComicInfoMetadata? {
        try storageManager.withScopedSourceAccess(for: descriptor) { session in
            let fileURL = resolveFileURL(for: comic, sourceRootURL: session.sourceURL)
            let extractedMetadata = try metadataExtractor.extractMetadata(for: fileURL)
            return extractedMetadata?.importedComicInfo
        }
    }

    private func uniqueComicsPreservingOrder(_ comics: [LibraryComic]) -> [LibraryComic] {
        var seen = Set<Int64>()
        var uniqueComics: [LibraryComic] = []
        uniqueComics.reserveCapacity(comics.count)

        for comic in comics where seen.insert(comic.id).inserted {
            uniqueComics.append(comic)
        }

        return uniqueComics
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

    private func progressPath(for comic: LibraryComic) -> String {
        let trimmedPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedPath.isEmpty ? comic.fileName : trimmedPath
    }
}
