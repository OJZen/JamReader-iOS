import Foundation
import os

final class LibraryMaintenanceStatusStore {
    private let repository: LibraryCatalogRepository

    init(fileManager: FileManager = .default) {
        let database = AppLibraryDatabase(fileManager: fileManager)
        let assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
        self.repository = LibraryCatalogRepository(database: database, assetStore: assetStore)
    }

    func loadRecord(for libraryID: UUID) -> LibraryMaintenanceRecord? {
        do {
            return try repository.loadMaintenanceRecord(for: libraryID)
        } catch {
            AppLog.persistence.error(
                "Library maintenance record load failed libraryID=\(libraryID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return nil
        }
    }

    func saveRecord(_ record: LibraryMaintenanceRecord) {
        do {
            try repository.saveMaintenanceRecord(record)
        } catch {
            AppLog.persistence.error(
                "Library maintenance record save failed libraryID=\(record.libraryID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }

    func clearRecord(for libraryID: UUID) {
        do {
            try repository.clearMaintenanceRecord(for: libraryID)
        } catch {
            AppLog.persistence.error(
                "Library maintenance record clear failed libraryID=\(libraryID.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }
}
