import Foundation
import os

extension Notification.Name {
    static let remoteBrowserPreferencesDidChange = Notification.Name(
        "JamReader.remoteBrowserPreferencesDidChange"
    )
}

final class RemoteBrowserPreferencesStore {
    static let defaultFolderImportScopeStorageKey = "remoteServerBrowser.defaultFolderImportScope"

    private let userDefaults: UserDefaults
    private let logger = AppLog.remote

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadDisplayMode(
        for serverID: UUID,
        defaultMode: LibraryComicDisplayMode
    ) -> LibraryComicDisplayMode {
        storedDisplayMode(for: serverID) ?? defaultMode
    }

    func saveDisplayMode(_ mode: LibraryComicDisplayMode, for serverID: UUID) {
        userDefaults.set(mode.rawValue, forKey: key(for: serverID, field: "displayMode"))
        logger.info(
            "Remote browser preference saved serverID=\(serverID.uuidString, privacy: .public) field=displayMode value=\(mode.rawValue, privacy: .public)"
        )
    }

    func storedDisplayMode(for serverID: UUID) -> LibraryComicDisplayMode? {
        if let rawValue = userDefaults.string(forKey: key(for: serverID, field: "displayMode")) {
            if let mode = LibraryComicDisplayMode(rawValue: rawValue) {
                return mode
            }
            logger.warning(
                "Remote browser preference ignored serverID=\(serverID.uuidString, privacy: .public) field=displayMode rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public)"
            )
        }

        if let legacyRawValue = userDefaults.string(forKey: legacyDisplayModeKey) {
            if let legacyMode = LibraryComicDisplayMode(rawValue: legacyRawValue) {
                return legacyMode
            }
            logger.warning(
                "Remote browser legacy preference ignored field=displayMode rawValue=\(AppLogSanitizer.truncated(legacyRawValue), privacy: .public)"
            )
        }

        return nil
    }

    func loadSortMode(for serverID: UUID) -> RemoteDirectorySortMode {
        if let rawValue = userDefaults.string(forKey: key(for: serverID, field: "sortMode")) {
            if let mode = RemoteDirectorySortMode(rawValue: rawValue) {
                return mode
            }
            logger.warning(
                "Remote browser preference ignored serverID=\(serverID.uuidString, privacy: .public) field=sortMode rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public)"
            )
        }

        if let legacyRawValue = userDefaults.string(forKey: legacySortModeKey) {
            if let legacyMode = RemoteDirectorySortMode(rawValue: legacyRawValue) {
                return legacyMode
            }
            logger.warning(
                "Remote browser legacy preference ignored field=sortMode rawValue=\(AppLogSanitizer.truncated(legacyRawValue), privacy: .public)"
            )
        }

        return .nameAscending
    }

    func saveSortMode(_ mode: RemoteDirectorySortMode, for serverID: UUID) {
        userDefaults.set(mode.rawValue, forKey: key(for: serverID, field: "sortMode"))
        logger.info(
            "Remote browser preference saved serverID=\(serverID.uuidString, privacy: .public) field=sortMode value=\(mode.rawValue, privacy: .public)"
        )
    }

    func loadDefaultFolderImportScope() -> RemoteDirectoryImportScope {
        guard let rawValue = userDefaults.string(
            forKey: Self.defaultFolderImportScopeStorageKey
        ) else {
            return .includeSubfolders
        }

        guard let scope = RemoteDirectoryImportScope(rawValue: rawValue),
              scope == .currentFolderOnly || scope == .includeSubfolders else {
            userDefaults.set(
                RemoteDirectoryImportScope.includeSubfolders.rawValue,
                forKey: Self.defaultFolderImportScopeStorageKey
            )
            logger.warning(
                "Remote browser import scope ignored rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public) fallback=\(RemoteDirectoryImportScope.includeSubfolders.rawValue, privacy: .public)"
            )
            return .includeSubfolders
        }

        return scope
    }

    func saveDefaultFolderImportScope(_ scope: RemoteDirectoryImportScope) {
        guard scope == .currentFolderOnly || scope == .includeSubfolders else {
            return
        }

        let previousValue = userDefaults.string(
            forKey: Self.defaultFolderImportScopeStorageKey
        )
        guard previousValue != scope.rawValue else {
            return
        }

        userDefaults.set(
            scope.rawValue,
            forKey: Self.defaultFolderImportScopeStorageKey
        )
        logger.info(
            "Remote browser preference saved field=defaultFolderImportScope value=\(scope.rawValue, privacy: .public)"
        )
        NotificationCenter.default.post(
            name: .remoteBrowserPreferencesDidChange,
            object: self
        )
    }

    private func key(for serverID: UUID, field: String) -> String {
        "remoteServerBrowser.\(serverID.uuidString).\(field)"
    }

    private let legacyDisplayModeKey = "remoteServerBrowser.displayMode"
    private let legacySortModeKey = "remoteServerBrowser.sortMode"
}
