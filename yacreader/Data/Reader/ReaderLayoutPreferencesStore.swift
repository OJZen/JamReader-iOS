import Foundation

final class ReaderLayoutPreferencesStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadLayout(for type: LibraryFileType) -> ReaderDisplayLayout {
        let scope = ReaderLayoutPreferenceScope(type: type)
        var layout = ReaderDisplayLayout(defaultsFor: type)

        if let rawSpreadMode = userDefaults.string(forKey: key(for: scope, field: "spreadMode")),
           let spreadMode = ReaderSpreadMode(rawValue: rawSpreadMode) {
            layout.spreadMode = spreadMode
        }

        if let rawReadingDirection = userDefaults.string(forKey: key(for: scope, field: "readingDirection")),
           let readingDirection = ReaderReadingDirection(rawValue: rawReadingDirection) {
            layout.readingDirection = readingDirection
        }

        if let rawFitMode = userDefaults.string(forKey: key(for: scope, field: "fitMode")),
           let fitMode = ReaderFitMode(rawValue: rawFitMode) {
            layout.fitMode = fitMode
        }

        if userDefaults.object(forKey: key(for: scope, field: "coverAsSinglePage")) != nil {
            layout.coverAsSinglePage = userDefaults.bool(forKey: key(for: scope, field: "coverAsSinglePage"))
        }

        return layout
    }

    func saveLayout(_ layout: ReaderDisplayLayout, for type: LibraryFileType) {
        let scope = ReaderLayoutPreferenceScope(type: type)
        userDefaults.set(layout.spreadMode.rawValue, forKey: key(for: scope, field: "spreadMode"))
        userDefaults.set(layout.readingDirection.rawValue, forKey: key(for: scope, field: "readingDirection"))
        userDefaults.set(layout.fitMode.rawValue, forKey: key(for: scope, field: "fitMode"))
        userDefaults.set(layout.coverAsSinglePage, forKey: key(for: scope, field: "coverAsSinglePage"))
    }

    private func key(for scope: ReaderLayoutPreferenceScope, field: String) -> String {
        "reader.layout.\(scope.rawValue).\(field)"
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
