import Foundation

final class SQLiteDatabaseInspector {
    private let repository: LibraryStateRepository

    init(fileManager: FileManager = .default) {
        self.repository = LibraryStateRepository(database: AppLibraryDatabase(fileManager: fileManager))
    }

    func inspectDatabase(at url: URL) -> LibraryDatabaseSummary {
        do {
            return try repository.summary(for: url)
        } catch {
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
