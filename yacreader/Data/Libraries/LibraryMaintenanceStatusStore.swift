import Foundation

final class LibraryMaintenanceStatusStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRecord(for libraryID: UUID) -> LibraryMaintenanceRecord? {
        userDefaults.decodable(LibraryMaintenanceRecord.self, forKey: storageKey(for: libraryID))
    }

    func saveRecord(_ record: LibraryMaintenanceRecord) {
        userDefaults.setEncodable(record, forKey: storageKey(for: record.libraryID))
    }

    func clearRecord(for libraryID: UUID) {
        userDefaults.removeObject(forKey: storageKey(for: libraryID))
    }

    private func storageKey(for libraryID: UUID) -> String {
        "libraryMaintenanceStatus.\(libraryID.uuidString)"
    }
}
