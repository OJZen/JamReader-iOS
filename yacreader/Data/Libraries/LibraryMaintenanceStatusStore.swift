import Foundation

final class LibraryMaintenanceStatusStore {
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRecord(for libraryID: UUID) -> LibraryMaintenanceRecord? {
        guard let data = userDefaults.data(forKey: storageKey(for: libraryID)) else {
            return nil
        }

        return try? decoder.decode(LibraryMaintenanceRecord.self, from: data)
    }

    func saveRecord(_ record: LibraryMaintenanceRecord) {
        guard let data = try? encoder.encode(record) else {
            return
        }

        userDefaults.set(data, forKey: storageKey(for: record.libraryID))
    }

    func clearRecord(for libraryID: UUID) {
        userDefaults.removeObject(forKey: storageKey(for: libraryID))
    }

    private func storageKey(for libraryID: UUID) -> String {
        "libraryMaintenanceStatus.\(libraryID.uuidString)"
    }
}
