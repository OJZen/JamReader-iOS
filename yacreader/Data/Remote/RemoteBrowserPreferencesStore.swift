import Foundation

final class RemoteBrowserPreferencesStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadDisplayMode(
        for serverID: UUID,
        defaultMode: LibraryComicDisplayMode
    ) -> LibraryComicDisplayMode {
        if let rawValue = userDefaults.string(forKey: key(for: serverID, field: "displayMode")),
           let mode = LibraryComicDisplayMode(rawValue: rawValue) {
            return mode
        }

        if let legacyRawValue = userDefaults.string(forKey: legacyDisplayModeKey),
           let legacyMode = LibraryComicDisplayMode(rawValue: legacyRawValue) {
            return legacyMode
        }

        return defaultMode
    }

    func saveDisplayMode(_ mode: LibraryComicDisplayMode, for serverID: UUID) {
        userDefaults.set(mode.rawValue, forKey: key(for: serverID, field: "displayMode"))
    }

    func loadSortMode(for serverID: UUID) -> RemoteDirectorySortMode {
        if let rawValue = userDefaults.string(forKey: key(for: serverID, field: "sortMode")),
           let mode = RemoteDirectorySortMode(rawValue: rawValue) {
            return mode
        }

        if let legacyRawValue = userDefaults.string(forKey: legacySortModeKey),
           let legacyMode = RemoteDirectorySortMode(rawValue: legacyRawValue) {
            return legacyMode
        }

        return .nameAscending
    }

    func saveSortMode(_ mode: RemoteDirectorySortMode, for serverID: UUID) {
        userDefaults.set(mode.rawValue, forKey: key(for: serverID, field: "sortMode"))
    }

    private func key(for serverID: UUID, field: String) -> String {
        "remoteServerBrowser.\(serverID.uuidString).\(field)"
    }

    private let legacyDisplayModeKey = "remoteServerBrowser.displayMode"
    private let legacySortModeKey = "remoteServerBrowser.sortMode"
}
