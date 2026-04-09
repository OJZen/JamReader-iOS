import Foundation

enum LibraryDatabaseWriteError: LocalizedError {
    case sqliteUnavailable
    case databaseMissing
    case openDatabaseFailed(String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .databaseMissing:
            return "This library has not been indexed yet."
        case .openDatabaseFailed(let reason):
            return "Unable to open the app library database for writing. \(reason)"
        case .updateFailed(let reason):
            return "Unable to update the app library database. \(reason)"
        }
    }
}

final class LibraryDatabaseWriter {
    private let repository: LibraryStateRepository

    init(fileManager: FileManager = .default) {
        self.repository = LibraryStateRepository(database: AppLibraryDatabase(fileManager: fileManager))
    }

    func updateReadingProgress(
        for comicID: Int64,
        progress: ComicReadingProgress,
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateReadingProgress(for: comicID, progress: progress, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func updateBookmarks(
        for comicID: Int64,
        bookmarkPageIndices: [Int],
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateBookmarks(for: comicID, bookmarkPageIndices: bookmarkPageIndices, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setFavorite(isFavorite, for: comicID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        do {
            try repository.setFavorite(isFavorite, for: comicIDs, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setReadStatus(isRead, for: comicID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setRating(
        _ rating: Double?,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setRating(rating, for: comicID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        do {
            try repository.setReadStatus(isRead, for: comicIDs, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func deleteComics(
        _ comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        do {
            try repository.deleteComics(comicIDs, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func createLabel(
        named name: String,
        color: LibraryLabelColor,
        in databaseURL: URL
    ) throws {
        do {
            try repository.createLabel(named: name, color: color, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func createReadingList(
        named name: String,
        in databaseURL: URL
    ) throws {
        do {
            try repository.createReadingList(named: name, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func updateLabel(
        id: Int64,
        named name: String,
        color: LibraryLabelColor,
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateLabel(id: id, named: name, color: color, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func updateReadingList(
        id: Int64,
        named name: String,
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateReadingList(id: id, named: name, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func deleteLabel(
        id: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.deleteLabel(id: id, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func deleteReadingList(
        id: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.deleteReadingList(id: id, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicID: Int64,
        labelID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setLabelMembership(isMember, comicID: comicID, labelID: labelID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        labelID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setLabelMembership(isMember, comicIDs: comicIDs, labelID: labelID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicID: Int64,
        readingListID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setReadingListMembership(isMember, comicID: comicID, readingListID: readingListID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        readingListID: Int64,
        in databaseURL: URL
    ) throws {
        do {
            try repository.setReadingListMembership(isMember, comicIDs: comicIDs, readingListID: readingListID, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func updateComicMetadata(
        _ metadata: LibraryComicMetadata,
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateComicMetadata(metadata, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func updateComicMetadata(
        _ patch: BatchComicMetadataPatch,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        do {
            try repository.updateComicMetadata(patch, for: comicIDs, in: databaseURL)
        } catch {
            throw mappedError(error)
        }
    }

    func applyImportedComicInfo(
        _ metadata: ImportedComicInfoMetadata,
        for comicID: Int64,
        in databaseURL: URL,
        policy: ComicInfoImportPolicy = .overwriteExisting
    ) throws {
        do {
            try repository.applyImportedComicInfo(metadata, for: comicID, in: databaseURL, policy: policy)
        } catch {
            throw mappedError(error)
        }
    }

    private func mappedError(_ error: Error) -> LibraryDatabaseWriteError {
        if let error = error as? LibraryDatabaseWriteError {
            return error
        }

        return .updateFailed(error.userFacingMessage)
    }
}
