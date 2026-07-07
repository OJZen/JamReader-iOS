import Foundation
import os

final class ReaderLayoutPreferencesStore {
    private let userDefaults: UserDefaults
    private let logger = AppLog.reader

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
        let scope = ReaderLayoutPreferenceScope(type: type)
        userDefaults.set(layout.pagingMode.rawValue, forKey: key(for: scope, field: "pagingMode"))
        userDefaults.set(layout.spreadMode.rawValue, forKey: key(for: scope, field: "spreadMode"))
        userDefaults.set(layout.readingDirection.rawValue, forKey: key(for: scope, field: "readingDirection"))
        userDefaults.set(layout.fitMode.rawValue, forKey: key(for: scope, field: "fitMode"))
        userDefaults.set(layout.coverAsSinglePage, forKey: key(for: scope, field: "coverAsSinglePage"))
        logger.info(
            """
            Reader layout preference saved type=\(type.rawValue, privacy: .public) \
            pagingMode=\(layout.pagingMode.rawValue, privacy: .public) \
            spreadMode=\(layout.spreadMode.rawValue, privacy: .public) \
            readingDirection=\(layout.readingDirection.rawValue, privacy: .public) \
            fitMode=\(layout.fitMode.rawValue, privacy: .public) \
            coverAsSinglePage=\(layout.coverAsSinglePage, privacy: .public)
            """
        )
    }

    private func key(for scope: ReaderLayoutPreferenceScope, field: String) -> String {
        "reader.layout.\(scope.rawValue).\(field)"
    }

    private func logIgnoredPreference(type: LibraryFileType, field: String, rawValue: String) {
        logger.warning(
            "Reader layout preference ignored type=\(type.rawValue, privacy: .public) field=\(field, privacy: .public) rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public)"
        )
    }
}

private enum ReaderLayoutPreferenceScope: String {
    case comic
    case manga

    init(type: LibraryFileType) {
        switch type {
        case .manga, .yonkoma:
            self = .manga
        case .comic, .westernManga, .webComic:
            self = .comic
        }
    }
}
