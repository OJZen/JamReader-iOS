import Foundation

enum LibraryFileType: Int, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case comic = 0
    case manga = 1
    case westernManga = 2
    case webComic = 3
    case yonkoma = 4

    var id: Int {
        rawValue
    }

    init(databaseValue: Int64?) {
        self = LibraryFileType(rawValue: Int(databaseValue ?? 0)) ?? .comic
    }

    var title: String {
        switch self {
        case .comic:
            return String(localized: "Comic")
        case .manga:
            return String(localized: "Manga")
        case .westernManga:
            return String(localized: "Western Manga")
        case .webComic:
            return String(localized: "Webcomic")
        case .yonkoma:
            return String(localized: "4-Koma")
        }
    }
}
