import Foundation

enum LibraryFileType: Int, Codable, Hashable, CaseIterable, Identifiable {
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
            return "Comic"
        case .manga:
            return "Manga"
        case .westernManga:
            return "Western Manga"
        case .webComic:
            return "Webcomic"
        case .yonkoma:
            return "4-Koma"
        }
    }
}
