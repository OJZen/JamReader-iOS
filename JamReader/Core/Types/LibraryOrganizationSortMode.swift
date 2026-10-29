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

extension Array where Element == LibraryOrganizationCollection {
    /// Ties fall back to the name so the order is stable.
    func sorted(by mode: LibraryOrganizationSortMode) -> [LibraryOrganizationCollection] {
        sorted { lhs, rhs in
            let byName = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            switch mode {
            case .name:
                return byName
            case .comicCountDescending:
                return lhs.comicCount == rhs.comicCount ? byName : lhs.comicCount > rhs.comicCount
            case .comicCountAscending:
                return lhs.comicCount == rhs.comicCount ? byName : lhs.comicCount < rhs.comicCount
            }
        }
    }
}
