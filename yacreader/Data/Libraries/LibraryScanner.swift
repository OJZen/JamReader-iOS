import Foundation

enum LibraryScannerError: LocalizedError {
    case sqliteUnavailable
    case databaseMissing
    case openDatabaseFailed(String)
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .databaseMissing:
            return "The app library database is not ready yet."
        case .openDatabaseFailed(let reason):
            return "Unable to open the app library database for scanning. \(reason)"
        case .scanFailed(let reason):
            return "Library scan failed. \(reason)"
        }
    }
}

final class LibraryScanner {
    private let indexingService: LibraryIndexingService

    init(fileManager: FileManager = .default) {
        let database = AppLibraryDatabase(fileManager: fileManager)
        let assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
        self.indexingService = LibraryIndexingService(
            database: database,
            assetStore: assetStore,
            fileManager: fileManager
        )
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        do {
            return try indexingService.scanLibrary(
                sourceRootURL: sourceRootURL,
                databaseURL: databaseURL,
                cancellationCheck: cancellationCheck,
                progressHandler: progressHandler
            )
        } catch {
            throw mappedError(error)
        }
    }

    func rescanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        do {
            return try indexingService.rescanLibrary(
                sourceRootURL: sourceRootURL,
                databaseURL: databaseURL,
                cancellationCheck: cancellationCheck,
                progressHandler: progressHandler
            )
        } catch {
            throw mappedError(error)
        }
    }

    func refreshFolder(
        sourceRootURL: URL,
        databaseURL: URL,
        folder: LibraryFolder,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        do {
            return try indexingService.refreshFolder(
                sourceRootURL: sourceRootURL,
                databaseURL: databaseURL,
                folder: folder,
                cancellationCheck: cancellationCheck,
                progressHandler: progressHandler
            )
        } catch {
            throw mappedError(error)
        }
    }

    func appendImportedComics(
        sourceRootURL: URL,
        databaseURL: URL,
        fileURLs: [URL],
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        do {
            return try indexingService.appendImportedComics(
                sourceRootURL: sourceRootURL,
                databaseURL: databaseURL,
                fileURLs: fileURLs,
                cancellationCheck: cancellationCheck,
                progressHandler: progressHandler
            )
        } catch {
            throw mappedError(error)
        }
    }

    private func mappedError(_ error: Error) -> LibraryScannerError {
        if let error = error as? LibraryScannerError {
            return error
        }

        return .scanFailed(error.userFacingMessage)
    }
}
