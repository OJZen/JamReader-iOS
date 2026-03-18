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
            return "Name"
        case .comicCountDescending:
            return "Most Comics"
        case .comicCountAscending:
            return "Fewest Comics"
        }
    }
}
