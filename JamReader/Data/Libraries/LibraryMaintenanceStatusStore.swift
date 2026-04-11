import Foundation

final class LibraryMaintenanceStatusStore {
    private let repository: LibraryCatalogRepository

    init(fileManager: FileManager = .default) {
        let database = AppLibraryDatabase(fileManager: fileManager)
        let assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
        self.repository = LibraryCatalogRepository(database: database, assetStore: assetStore)
    }

    func loadRecord(for libraryID: UUID) -> LibraryMaintenanceRecord? {
        try? repository.loadMaintenanceRecord(for: libraryID)
    }

    func saveRecord(_ record: LibraryMaintenanceRecord) {
        try? repository.saveMaintenanceRecord(record)
    }

    func clearRecord(for libraryID: UUID) {
        try? repository.clearMaintenanceRecord(for: libraryID)
    }
}
