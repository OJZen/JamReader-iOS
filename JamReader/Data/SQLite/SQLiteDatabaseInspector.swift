import Foundation
import os

final class SQLiteDatabaseInspector {
    private let repository: LibraryStateRepository
    private let logger = AppLog.persistence

    init(fileManager: FileManager = .default) {
        self.repository = LibraryStateRepository(database: AppLibraryDatabase(fileManager: fileManager))
    }

    func inspectDatabase(at url: URL) -> LibraryDatabaseSummary {
        do {
            return try repository.summary(for: url)
        } catch {
            logger.warning(
                "SQLite database inspect failed path=\(AppLogSanitizer.path(url.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return LibraryDatabaseSummary(
                exists: false,
                version: "AppLibraryV2",
                folderCount: 0,
                comicCount: 0,
                lastError: error.userFacingMessage
            )
        }
    }
}
