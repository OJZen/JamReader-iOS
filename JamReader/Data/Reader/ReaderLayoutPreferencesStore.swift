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
        "coverAsSinglePage",
        "pageSpacingEnabled"
    ]
    private static let sharedScope = "shared"
    private static let sharedScopeMigrationKey = "reader.layout.sharedScopeMigrated"

    private let userDefaults: UserDefaults
    private let logger = AppLog.reader

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        migrateLegacyPreferencesIfNeeded()
    }

    func loadLayout() -> ReaderDisplayLayout {
        loadLayout(
            from: Self.sharedScope,
            defaultLayout: ReaderDisplayLayout(),
            logScope: Self.sharedScope
        )
    }

    func saveLayout(_ layout: ReaderDisplayLayout) {
        var persistedLayout = layout
        persistedLayout.rotation = .degrees0
        guard loadLayout() != persistedLayout else {
            return
        }

        persist(persistedLayout, to: Self.sharedScope)
        logger.info(
            """
            Reader layout preference saved scope=shared \
            pagingMode=\(persistedLayout.pagingMode.rawValue, privacy: .public) \
            spreadMode=\(persistedLayout.spreadMode.rawValue, privacy: .public) \
            readingDirection=\(persistedLayout.readingDirection.rawValue, privacy: .public) \
            fitMode=\(persistedLayout.fitMode.rawValue, privacy: .public) \
            coverAsSinglePage=\(persistedLayout.coverAsSinglePage, privacy: .public) \
            pageSpacingEnabled=\(persistedLayout.pageSpacingEnabled, privacy: .public)
            """
        )
        notifyPreferencesChanged()
    }

    func resetLayout() {
        let storedKeys = Self.storedFields.map {
            key(for: Self.sharedScope, field: $0)
        }
        guard storedKeys.contains(where: { userDefaults.object(forKey: $0) != nil }) else {
            return
        }

        for storedKey in storedKeys {
            userDefaults.removeObject(forKey: storedKey)
        }
        logger.notice("Reader layout preference reset scope=shared")
        notifyPreferencesChanged()
    }

    private func loadLayout(
        from scope: String,
        defaultLayout: ReaderDisplayLayout,
        logScope: String
    ) -> ReaderDisplayLayout {
        var layout = defaultLayout

        if let rawSpreadMode = userDefaults.string(forKey: key(for: scope, field: "spreadMode")) {
            if let spreadMode = ReaderSpreadMode(rawValue: rawSpreadMode) {
                layout.spreadMode = spreadMode
            } else {
                logIgnoredPreference(scope: logScope, field: "spreadMode", rawValue: rawSpreadMode)
            }
        }

        if let rawReadingDirection = userDefaults.string(forKey: key(for: scope, field: "readingDirection")) {
            if let readingDirection = ReaderReadingDirection(rawValue: rawReadingDirection) {
                layout.readingDirection = readingDirection
            } else {
                logIgnoredPreference(scope: logScope, field: "readingDirection", rawValue: rawReadingDirection)
            }
        }

        if let rawPagingMode = userDefaults.string(forKey: key(for: scope, field: "pagingMode")) {
            if let pagingMode = ReaderPagingMode(rawValue: rawPagingMode) {
                layout.pagingMode = pagingMode
            } else {
                logIgnoredPreference(scope: logScope, field: "pagingMode", rawValue: rawPagingMode)
            }
        }

        if let rawFitMode = userDefaults.string(forKey: key(for: scope, field: "fitMode")) {
            if let fitMode = ReaderFitMode(rawValue: rawFitMode) {
                layout.fitMode = fitMode
            } else {
                logIgnoredPreference(scope: logScope, field: "fitMode", rawValue: rawFitMode)
            }
        }

        if userDefaults.object(forKey: key(for: scope, field: "coverAsSinglePage")) != nil {
            layout.coverAsSinglePage = userDefaults.bool(forKey: key(for: scope, field: "coverAsSinglePage"))
        }

        if userDefaults.object(forKey: key(for: scope, field: "pageSpacingEnabled")) != nil {
            layout.pageSpacingEnabled = userDefaults.bool(forKey: key(for: scope, field: "pageSpacingEnabled"))
        }

        return layout
    }

    private func persist(_ layout: ReaderDisplayLayout, to scope: String) {
        userDefaults.set(layout.pagingMode.rawValue, forKey: key(for: scope, field: "pagingMode"))
        userDefaults.set(layout.spreadMode.rawValue, forKey: key(for: scope, field: "spreadMode"))
        userDefaults.set(layout.readingDirection.rawValue, forKey: key(for: scope, field: "readingDirection"))
        userDefaults.set(layout.fitMode.rawValue, forKey: key(for: scope, field: "fitMode"))
        userDefaults.set(layout.coverAsSinglePage, forKey: key(for: scope, field: "coverAsSinglePage"))
        userDefaults.set(layout.pageSpacingEnabled, forKey: key(for: scope, field: "pageSpacingEnabled"))
    }

    private func key(for scope: String, field: String) -> String {
        "reader.layout.\(scope).\(field)"
    }

    private func logIgnoredPreference(scope: String, field: String, rawValue: String) {
        logger.warning(
            "Reader layout preference ignored scope=\(scope, privacy: .public) field=\(field, privacy: .public) rawValue=\(AppLogSanitizer.truncated(rawValue), privacy: .public)"
        )
    }

    private func notifyPreferencesChanged() {
        NotificationCenter.default.post(
            name: .readerLayoutPreferencesDidChange,
            object: self,
            userInfo: ["scope": Self.sharedScope]
        )
    }

    private func migrateLegacyPreferencesIfNeeded() {
        guard !userDefaults.bool(forKey: Self.sharedScopeMigrationKey) else {
            return
        }

        defer {
            userDefaults.set(true, forKey: Self.sharedScopeMigrationKey)
        }

        let sharedKeys = Self.storedFields.map {
            key(for: Self.sharedScope, field: $0)
        }
        guard !sharedKeys.contains(where: { userDefaults.object(forKey: $0) != nil }) else {
            return
        }

        // UserDefaults does not retain a reliable modification date per key.
        // Prefer the most complete legacy profile, with the former general
        // comic scope winning deterministic ties.
        var legacyScope: LegacyReaderLayoutPreferenceScope?
        var storedFieldCount = 0
        for scope in LegacyReaderLayoutPreferenceScope.allCases {
            let count = Self.storedFields.reduce(into: 0) { result, field in
                if userDefaults.object(forKey: key(for: scope.rawValue, field: field)) != nil {
                    result += 1
                }
            }
            if count > storedFieldCount {
                legacyScope = scope
                storedFieldCount = count
            }
        }

        guard let legacyScope else {
            return
        }

        let migratedLayout = loadLayout(
            from: legacyScope.rawValue,
            defaultLayout: ReaderDisplayLayout(defaultsFor: legacyScope.fileType),
            logScope: legacyScope.rawValue
        )
        persist(migratedLayout, to: Self.sharedScope)
        logger.notice(
            "Reader layout preference migrated source=\(legacyScope.rawValue, privacy: .public) destination=shared"
        )
    }
}

private enum LegacyReaderLayoutPreferenceScope: String, CaseIterable {
    case comic
    case manga
    case webComic

    var fileType: LibraryFileType {
        switch self {
        case .comic:
            return .comic
        case .manga:
            return .manga
        case .webComic:
            return .webComic
        }
    }
}
