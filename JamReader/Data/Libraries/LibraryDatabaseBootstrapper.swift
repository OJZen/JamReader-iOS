import Foundation

enum LibraryDatabaseBootstrapError: LocalizedError {
    case sqliteUnavailable
    case createDatabaseFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .createDatabaseFailed(let reason):
            return "Unable to initialize the app library database. \(reason)"
        }
    }
}

final class LibraryDatabaseBootstrapper {
    static let currentDatabaseVersion = "2"

    private let database: AppLibraryDatabase

    init(fileManager: FileManager = .default) {
        self.database = AppLibraryDatabase(fileManager: fileManager)
    }

    func ensureDatabaseExists(at databaseURL: URL) throws {
        _ = databaseURL
        try createDatabaseIfNeeded(at: databaseURL)
    }

    static func supportsDatabaseVersion(_ version: String?) -> Bool {
        _ = version
        return true
    }

    func createDatabaseIfNeeded(at databaseURL: URL) throws {
        _ = databaseURL
        do {
            try database.ensureInitialized()
        } catch {
            throw LibraryDatabaseBootstrapError.createDatabaseFailed(error.userFacingMessage)
        }
    }
}
