import Foundation
import os

extension Notification.Name {
    static let readerLayoutPreferencesDidChange = Notification.Name(
        "JamReader.readerLayoutPreferencesDidChange"
    )
}

final class ReaderLayoutPreferencesStore {
    private static let storedFields = [
        "pagingMode",
        "spreadMode",
        "readingDirection",
        "fitMode",
        "coverAsSinglePage"
    ]
    private static let webComicScopeMigrationKey = "reader.layout.webComicScopeMigrated"

    private let userDefaults: UserDefaults
    private let logger = AppLog.reader

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        migrateLegacyWebComicPreferencesIfNeeded()
    }

    func loadLayout(for type: LibraryFileType) -> ReaderDisplayLayout {
        let scope = ReaderLayoutPreferenceScope(type: type)
        var layout = ReaderDisplayLayout(defaultsFor: type)

        if let rawSpreadMode = userDefaults.string(forKey: key(for: scope, field: "spreadMode")) {
            if let spreadMode = ReaderSpreadMode(rawValue: rawSpreadMode) {
                layout.spreadMode = spreadMode
            } else {
                logIgnoredPreference(type: type, field: "spreadMode", rawValue: rawSpreadMode)
            }
        }

        if let rawReadingDirection = userDefaults.string(forKey: key(for: scope, field: "readingDirection")) {
            if let readingDirection = ReaderReadingDirection(rawValue: rawReadingDirection) {
                layout.readingDirection = readingDirection
            } else {
                logIgnoredPreference(type: type, field: "readingDirection", rawValue: rawReadingDirection)
            }
        }

        if let rawPagingMode = userDefaults.string(forKey: key(for: scope, field: "pagingMode")) {
            if let pagingMode = ReaderPagingMode(rawValue: rawPagingMode) {
                layout.pagingMode = pagingMode
            } else {
                logIgnoredPreference(type: type, field: "pagingMode", rawValue: rawPagingMode)
            }
        }

        if let rawFitMode = userDefaults.string(forKey: key(for: scope, field: "fitMode")) {
            if let fitMode = ReaderFitMode(rawValue: rawFitMode) {
                layout.fitMode = fitMode
            } else {
                logIgnoredPreference(type: type, field: "fitMode", rawValue: rawFitMode)
            }
        }

        if userDefaults.object(forKey: key(for: scope, field: "coverAsSinglePage")) != nil {
            layout.coverAsSinglePage = userDefaults.bool(forKey: key(for: scope, field: "coverAsSinglePage"))
        }

        return layout
    }

    func saveLayout(_ layout: ReaderDisplayLayout, for type: LibraryFileType) {
        var persistedLayout = layout
        persistedLayout.rotation = .degrees0
        guard loadLayout(for: type) != persistedLayout else {
            return
        }

        let scope = ReaderLayoutPreferenceScope(type: type)
        userDefaults.set(persistedLayout.pagingMode.rawValue, forKey: key(for: scope, field: "pagingMode"))
        userDefaults.set(persistedLayout.spreadMode.rawValue, forKey: key(for: scope, field: "spreadMode"))
        userDefaults.set(persistedLayout.readingDirection.rawValue, forKey: key(for: scope, field: "readingDirection"))
        userDefaults.set(persistedLayout.fitMode.rawValue, forKey: key(for: scope, field: "fitMode"))
        userDefaults.set(persistedLayout.coverAsSinglePage, forKey: key(for: scope, field: "coverAsSinglePage"))
        logger.info(
            """
            Reader layout preference saved type=\(type.rawValue, privacy: .public) \
            pagingMode=\(persistedLayout.pagingMode.rawValue, privacy: .public) \
            spreadMode=\(persistedLayout.spreadMode.rawValue, privacy: .public) \
            readingDirection=\(persistedLayout.readingDirection.rawValue, privacy: .public) \
            fitMode=\(persistedLayout.fitMode.rawValue, privacy: .public) \
            coverAsSinglePage=\(persistedLayout.coverAsSinglePage, privacy: .public)
            """
        )
        notifyPreferencesChanged(for: type)
    }

    func resetLayout(for type: LibraryFileType) {
        let scope = ReaderLayoutPreferenceScope(type: type)
        let storedKeys = Self.storedFields.map { key(for: scope, field: $0) }
        guard storedKeys.contains(where: { userDefaults.object(forKey: $0) != nil }) else {
            return
        }

        for storedKey in storedKeys {
            userDefaults.removeObject(forKey: storedKey)
        }
        logger.notice(
            "Reader layout preference reset type=\(type.rawValue, privacy: .public)"
        )
        notifyPreferencesChanged(for: type)
    }

    private func key(for scope: ReaderLayoutPreferenceScope, field: String) -> String {
        "reader.layout.\(scope.rawValue).\(field)"
    }

    private func logIgnoredPreference(type: LibraryFileType, field: String, rawValue: String) {
        logger.warning(
            "Reader layout preference ignored type=\(type.rawValue, privacy: .public) field=\(field, privacy: .public) rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public)"
        )
    }

    private func notifyPreferencesChanged(for type: LibraryFileType) {
        NotificationCenter.default.post(
            name: .readerLayoutPreferencesDidChange,
            object: self,
            userInfo: ["type": type.rawValue]
        )
    }

    private func migrateLegacyWebComicPreferencesIfNeeded() {
        guard !userDefaults.bool(forKey: Self.webComicScopeMigrationKey) else {
            return
        }

        var copiedFieldCount = 0
        for field in Self.storedFields {
            let legacyKey = key(for: .comic, field: field)
            let destinationKey = key(for: .webComic, field: field)
            guard userDefaults.object(forKey: destinationKey) == nil,
                  let legacyValue = userDefaults.object(forKey: legacyKey)
            else {
                continue
            }

            userDefaults.set(legacyValue, forKey: destinationKey)
            copiedFieldCount += 1
        }

        userDefaults.set(true, forKey: Self.webComicScopeMigrationKey)
        guard copiedFieldCount > 0 else {
            return
        }

        logger.notice(
            "Reader layout webcomic scope migrated copiedFields=\(copiedFieldCount, privacy: .public)"
        )
    }
}

private enum ReaderLayoutPreferenceScope: String {
    case comic
    case manga
    case webComic

    init(type: LibraryFileType) {
        switch type {
        case .manga, .yonkoma:
            self = .manga
        case .webComic:
            self = .webComic
        case .comic, .westernManga:
            self = .comic
        }
    }
}
