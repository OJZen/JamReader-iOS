import Foundation

enum LibraryDatabaseReadError: LocalizedError {
    case databaseMissing
    case sqliteUnavailable
    case openDatabaseFailed(String)
    case folderNotFound(Int64)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing:
            return "This library has not been indexed yet."
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .openDatabaseFailed(let reason):
            return "Unable to open the app library database. \(reason)"
        case .folderNotFound(let folderID):
            return "The requested folder \(folderID) could not be found in the local library state."
        case .queryFailed(let reason):
            return "Library query failed. \(reason)"
        }
    }
}

final class LibraryDatabaseReader {
    private let repository: LibraryStateRepository

    init(fileManager: FileManager = .default) {
        self.repository = LibraryStateRepository(database: AppLibraryDatabase(fileManager: fileManager))
    }

    func loadFolderContent(databaseURL: URL, folderID: Int64 = 1) throws -> LibraryFolderContent {
        do {
            return try repository.loadFolderContent(databaseURL: databaseURL, folderID: folderID)
        } catch {
            throw mappedError(error, fallbackFolderID: folderID)
        }
    }

    func searchLibrary(
        databaseURL: URL,
        query: String,
        limit: Int = 40
    ) throws -> LibrarySearchResults {
        do {
            return try repository.searchLibrary(databaseURL: databaseURL, query: query, limit: limit)
        } catch {
            throw mappedError(error)
        }
    }

    func loadSpecialListComics(
        databaseURL: URL,
        kind: LibrarySpecialCollectionKind,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        do {
            return try repository.loadSpecialListComics(
                databaseURL: databaseURL,
                kind: kind,
                recentDays: recentDays,
                limit: limit
            )
        } catch {
            throw mappedError(error)
        }
    }

    func loadSpecialListCounts(
        databaseURL: URL,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays
    ) throws -> [LibrarySpecialCollectionKind: Int] {
        do {
            return try repository.loadSpecialListCounts(databaseURL: databaseURL, recentDays: recentDays)
        } catch {
            throw mappedError(error)
        }
    }

    func loadOrganizationSnapshot(databaseURL: URL) throws -> LibraryOrganizationSnapshot {
        do {
            return try repository.loadOrganizationSnapshot(databaseURL: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func loadComicOrganizationSnapshot(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryOrganizationSnapshot {
        do {
            return try repository.loadComicOrganizationSnapshot(databaseURL: databaseURL, comicID: comicID)
        } catch {
            throw mappedError(error)
        }
    }

    func loadOrganizationComics(
        databaseURL: URL,
        collection: LibraryOrganizationCollection
    ) throws -> [LibraryComic] {
        do {
            return try repository.loadOrganizationComics(databaseURL: databaseURL, collection: collection)
        } catch {
            throw mappedError(error)
        }
    }

    func loadAllComics(databaseURL: URL) throws -> [LibraryComic] {
        do {
            return try repository.loadAllComics(databaseURL: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func loadComicsRecursively(
        databaseURL: URL,
        folderID: Int64
    ) throws -> [LibraryComic] {
        do {
            return try repository.loadComicsRecursively(databaseURL: databaseURL, folderID: folderID)
        } catch {
            throw mappedError(error, fallbackFolderID: folderID)
        }
    }

    func loadComicMetadata(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryComicMetadata {
        do {
            return try repository.loadComicMetadata(databaseURL: databaseURL, comicID: comicID)
        } catch {
            throw mappedError(error)
        }
    }

    private func mappedError(_ error: Error, fallbackFolderID: Int64? = nil) -> LibraryDatabaseReadError {
        if let error = error as? LibraryDatabaseReadError {
            return error
        }

        if let fallbackFolderID {
            return .folderNotFound(fallbackFolderID)
        }

        return .queryFailed(error.userFacingMessage)
    }
}
