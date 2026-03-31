import Foundation

enum LibraryComicRemovalError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

final class LibraryComicRemovalService {
    private let storageManager: LibraryStorageManager
    private let databaseWriter: LibraryDatabaseWriter
    private let coverLocator: LibraryCoverLocator
    private let databaseInspector: SQLiteDatabaseInspector
    private let fileManager: FileManager

    init(
        storageManager: LibraryStorageManager,
        databaseWriter: LibraryDatabaseWriter,
        coverLocator: LibraryCoverLocator,
        databaseInspector: SQLiteDatabaseInspector = SQLiteDatabaseInspector(),
        fileManager: FileManager = .default
    ) {
        self.storageManager = storageManager
        self.databaseWriter = databaseWriter
        self.coverLocator = coverLocator
        self.databaseInspector = databaseInspector
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

        if let message = removalAvailabilityMessage(for: descriptor) {
            throw LibraryComicRemovalError.unavailable(message)
        }

        let databaseURL = storageManager.databaseURL(for: descriptor)
        let metadataRootURL = storageManager.metadataRootURL(for: descriptor)

        try storageManager.withScopedSourceAccess(for: descriptor) { session in
            let sourceRootURL = session.sourceURL.standardizedFileURL

            for comic in uniqueComics {
                let comicFileURL = resolveComicFileURL(
                    for: comic,
                    sourceRootURL: sourceRootURL
                )

                if fileManager.fileExists(atPath: comicFileURL.path) {
                    try fileManager.removeItem(at: comicFileURL)
                }

                let coverURL = coverLocator.plannedCoverURL(
                    for: comic,
                    metadataRootURL: metadataRootURL
                )
                if fileManager.fileExists(atPath: coverURL.path) {
                    try? fileManager.removeItem(at: coverURL)
                }
            }

            try databaseWriter.deleteComics(
                uniqueComics.map(\.id),
                in: databaseURL
            )
        }
    }

    private func removalAvailabilityMessage(
        for descriptor: LibraryDescriptor
    ) -> String? {
        if descriptor.storageMode == .mirrored {
            return "This library is browse-only on this device, so comics cannot be removed here."
        }

        let accessSnapshot = storageManager.accessSnapshot(
            for: descriptor,
            inspector: databaseInspector
        )

        if accessSnapshot.database.exists && !accessSnapshot.database.hasCompatibleSchemaVersion {
            let versionText = accessSnapshot.database.version ?? "Unknown"
            return "This library uses DB \(versionText), which cannot be modified from this iOS build."
        }

        if !accessSnapshot.sourceWritable {
            return "This library is currently read-only on this device."
        }

        return nil
    }

    private func resolveComicFileURL(
        for comic: LibraryComic,
        sourceRootURL: URL
    ) -> URL {
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
