import Foundation

enum LibraryOrganizationSortMode: String, CaseIterable, Identifiable {
    case name
    case comicCountDescending
    case comicCountAscending

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .name:
            return String(localized: "Name")
        case .comicCountDescending:
            return String(localized: "Most Comics")
        case .comicCountAscending:
            return String(localized: "Fewest Comics")
        }
    }
}
