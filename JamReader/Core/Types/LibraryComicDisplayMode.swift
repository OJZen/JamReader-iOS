import Foundation

enum LibraryComicDisplayMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .list:
            return String(localized: "List")
        case .grid:
            return String(localized: "Grid")
        }
    }

    var systemImageName: String {
        switch self {
        case .list:
            return "list.bullet"
        case .grid:
            return "square.grid.2x2"
        }
    }
}
