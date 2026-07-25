import Foundation
import os

enum LibraryComicRemovalError: LocalizedError {
    case unavailable(String)
    case unsafeComicPath

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .unsafeComicPath:
            return String(localized: "A comic points outside the library folder and could not be removed safely.")
        }
    }
}

protocol LibraryComicDatabaseDeleting {
    func deleteComics(
        _ comicIDs: [Int64],
        in databaseURL: URL
    ) throws
}

extension LibraryDatabaseWriter: LibraryComicDatabaseDeleting {}

protocol LibraryComicRemovalFileManaging {
    func fileExists(atPath path: String) -> Bool
    func destinationOfSymbolicLink(atPath path: String) throws -> String
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func removeItem(at url: URL) throws
}

extension FileManager: LibraryComicRemovalFileManaging {}

final class LibraryComicRemovalService {
    private struct QuarantinedComicFile {
        let comicID: Int64
        let originalURL: URL
        let quarantineURL: URL
    }

    private let storageManager: LibraryStorageManager
    private let databaseWriter: any LibraryComicDatabaseDeleting
    private let coverLocator: LibraryCoverLocator
    private let fileManager: any LibraryComicRemovalFileManaging
    private let logger = AppLog.library

    init(
        storageManager: LibraryStorageManager,
        databaseWriter: any LibraryComicDatabaseDeleting,
        coverLocator: LibraryCoverLocator,
        fileManager: any LibraryComicRemovalFileManaging = FileManager.default
    ) {
        self.storageManager = storageManager
        self.databaseWriter = databaseWriter
        self.coverLocator = coverLocator
        self.fileManager = fileManager
    }

    func canRemoveComics(from descriptor: LibraryDescriptor) -> Bool {
        removalAvailabilityMessage(for: descriptor) == nil
    }

    func removeComic(
        _ comic: LibraryComic,
        from descriptor: LibraryDescriptor
    ) throws {
        try removeComics([comic], from: descriptor)
    }

    func removeComics(
        _ comics: [LibraryComic],
        from descriptor: LibraryDescriptor
    ) throws {
        let uniqueComics = uniqueComicsPreservingOrder(comics)
        guard !uniqueComics.isEmpty else {
            return
        }

        let libraryID = descriptor.id.uuidString
        let comicNames = AppLogSanitizer.namesPreview(uniqueComics.map(\.displayTitle))
        logger.info(
            "Library comic removal requested libraryID=\(libraryID, privacy: .public) count=\(uniqueComics.count) comics=\(comicNames, privacy: .public)"
        )

        if let message = removalAvailabilityMessage(for: descriptor) {
            logger.warning(
                "Library comic removal rejected libraryID=\(libraryID, privacy: .public) count=\(uniqueComics.count) reason=\(AppLogSanitizer.truncated(message), privacy: .public)"
            )
            throw LibraryComicRemovalError.unavailable(message)
        }

        let databaseURL = storageManager.databaseURL(for: descriptor)
        let metadataRootURL = storageManager.metadataRootURL(for: descriptor)

        do {
            try storageManager.withScopedSourceAccess(for: descriptor) { session in
                let sourceRootURL = session.sourceURL.standardizedFileURL
                let comicFileURLs = try uniqueComics.map { comic in
                    try validatedComicFileURL(
                        for: comic,
                        sourceRootURL: sourceRootURL
                    )
                }
                var quarantinedFiles: [QuarantinedComicFile] = []
                var quarantineRootURL: URL?

                do {
                    for (index, comic) in uniqueComics.enumerated() {
                        let comicFileURL = comicFileURLs[index]
                        guard itemExists(at: comicFileURL) else {
                            continue
                        }

                        let transactionRootURL: URL
                        if let quarantineRootURL {
                            transactionRootURL = quarantineRootURL
                        } else {
                            transactionRootURL = sourceRootURL.appendingPathComponent(
                                ".jamreader-removal-\(UUID().uuidString)",
                                isDirectory: true
                            )
                            try fileManager.createDirectory(
                                at: transactionRootURL,
                                withIntermediateDirectories: false,
                                attributes: nil
                            )
                            quarantineRootURL = transactionRootURL
                        }

                        let quarantineURL = transactionRootURL.appendingPathComponent(
                            "\(index)-\(comic.id)-\(UUID().uuidString)",
                            isDirectory: false
                        )
                        try fileManager.moveItem(at: comicFileURL, to: quarantineURL)
                        quarantinedFiles.append(
                            QuarantinedComicFile(
                                comicID: comic.id,
                                originalURL: comicFileURL,
                                quarantineURL: quarantineURL
                            )
                        )
                    }

                    try databaseWriter.deleteComics(
                        uniqueComics.map(\.id),
                        in: databaseURL
                    )
                } catch {
                    rollbackQuarantinedFiles(
                        quarantinedFiles,
                        quarantineRootURL: quarantineRootURL,
                        libraryID: libraryID
                    )
                    throw error
                }

                cleanupCommittedQuarantine(
                    at: quarantineRootURL,
                    libraryID: libraryID
                )
                cleanupCovers(
                    for: uniqueComics,
                    metadataRootURL: metadataRootURL,
                    libraryID: libraryID
                )
            }

            logger.info(
                "Library comic removal completed libraryID=\(libraryID, privacy: .public) count=\(uniqueComics.count)"
            )
        } catch {
            logger.error(
                "Library comic removal failed libraryID=\(libraryID, privacy: .public) count=\(uniqueComics.count) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            throw error
        }
    }

    private func removalAvailabilityMessage(
        for descriptor: LibraryDescriptor
    ) -> String? {
        let accessSnapshot = storageManager.accessSnapshot(
            for: descriptor,
            inspector: SQLiteDatabaseInspector()
        )

        if !accessSnapshot.sourceWritable {
            return String(localized: "This library is currently read-only on this device.")
        }

        return nil
    }

    private func validatedComicFileURL(
        for comic: LibraryComic,
        sourceRootURL: URL
    ) throws -> URL {
        let relativePath = {
            let rawPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawPath.isEmpty {
                return comic.fileName
            }

            return rawPath
        }()

        let candidateURL: URL
        if relativePath.hasPrefix("/") {
            candidateURL = sourceRootURL.appendingPathComponent(String(relativePath.dropFirst()))
        } else {
            candidateURL = sourceRootURL.appendingPathComponent(relativePath)
        }

        let resolvedSourceRootURL = sourceRootURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let standardizedCandidateURL = candidateURL.standardizedFileURL
        let resolvedParentURL = standardizedCandidateURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let resolvedCandidateURL = standardizedCandidateURL.resolvingSymlinksInPath()
        let rootPath = resolvedSourceRootURL.path
        let rootDescendantPrefix = rootPath == "/" ? rootPath : rootPath + "/"
        let parentIsWithinRoot = resolvedParentURL.path == rootPath
            || resolvedParentURL.path.hasPrefix(rootDescendantPrefix)
        let candidateIsWithinRoot = resolvedCandidateURL.path.hasPrefix(rootDescendantPrefix)
        guard parentIsWithinRoot, candidateIsWithinRoot else {
            logger.warning(
                "Library comic removal rejected unsafe path comicID=\(comic.id, privacy: .public) root=\(AppLogSanitizer.path(rootPath), privacy: .public)"
            )
            throw LibraryComicRemovalError.unsafeComicPath
        }

        return standardizedCandidateURL
    }

    private func itemExists(at url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return true
        }

        do {
            _ = try fileManager.destinationOfSymbolicLink(atPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private func rollbackQuarantinedFiles(
        _ quarantinedFiles: [QuarantinedComicFile],
        quarantineRootURL: URL?,
        libraryID: String
    ) {
        var restoredAllFiles = true

        for quarantinedFile in quarantinedFiles.reversed() {
            guard itemExists(at: quarantinedFile.quarantineURL) else {
                if !itemExists(at: quarantinedFile.originalURL) {
                    restoredAllFiles = false
                    logger.error(
                        "Library comic rollback source missing libraryID=\(libraryID, privacy: .public) comicID=\(quarantinedFile.comicID, privacy: .public)"
                    )
                }
                continue
            }

            guard !itemExists(at: quarantinedFile.originalURL) else {
                restoredAllFiles = false
                logger.error(
                    "Library comic rollback destination occupied libraryID=\(libraryID, privacy: .public) comicID=\(quarantinedFile.comicID, privacy: .public) path=\(AppLogSanitizer.path(quarantinedFile.originalURL.path), privacy: .public)"
                )
                continue
            }

            do {
                try fileManager.moveItem(
                    at: quarantinedFile.quarantineURL,
                    to: quarantinedFile.originalURL
                )
            } catch {
                restoredAllFiles = false
                logger.error(
                    "Library comic rollback failed libraryID=\(libraryID, privacy: .public) comicID=\(quarantinedFile.comicID, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
        }

        guard restoredAllFiles, let quarantineRootURL else {
            return
        }

        removeQuarantineDirectoryBestEffort(
            at: quarantineRootURL,
            libraryID: libraryID,
            operation: "rollbackCleanup"
        )
    }

    private func cleanupCommittedQuarantine(
        at quarantineRootURL: URL?,
        libraryID: String
    ) {
        guard let quarantineRootURL else {
            return
        }

        removeQuarantineDirectoryBestEffort(
            at: quarantineRootURL,
            libraryID: libraryID,
            operation: "commitCleanup"
        )
    }

    private func removeQuarantineDirectoryBestEffort(
        at quarantineRootURL: URL,
        libraryID: String,
        operation: String
    ) {
        guard fileManager.fileExists(atPath: quarantineRootURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: quarantineRootURL)
        } catch {
            logger.warning(
                "Library comic quarantine cleanup failed libraryID=\(libraryID, privacy: .public) operation=\(operation, privacy: .public) path=\(AppLogSanitizer.path(quarantineRootURL.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }

    private func cleanupCovers(
        for comics: [LibraryComic],
        metadataRootURL: URL,
        libraryID: String
    ) {
        for comic in comics {
            let coverURL = coverLocator.plannedCoverURL(
                for: comic,
                metadataRootURL: metadataRootURL
            )
            guard fileManager.fileExists(atPath: coverURL.path) else {
                continue
            }

            do {
                try fileManager.removeItem(at: coverURL)
            } catch {
                logger.warning(
                    "Library comic cover cleanup failed libraryID=\(libraryID, privacy: .public) comicID=\(comic.id, privacy: .public) path=\(AppLogSanitizer.path(coverURL.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
        }
    }

    private func uniqueComicsPreservingOrder(_ comics: [LibraryComic]) -> [LibraryComic] {
        var seen = Set<Int64>()
        var ordered: [LibraryComic] = []
        ordered.reserveCapacity(comics.count)

        for comic in comics where seen.insert(comic.id).inserted {
            ordered.append(comic)
        }

        return ordered
    }
}
