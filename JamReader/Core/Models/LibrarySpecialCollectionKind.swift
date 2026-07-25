import Foundation

enum LibrarySpecialCollectionKind: String, CaseIterable, Hashable, Identifiable {
    case reading
    case favorites
    case recent

    static let defaultRecentDays = 7

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .reading:
            return String(localized: "Reading")
        case .favorites:
            return String(localized: "Favorites")
        case .recent:
            return String(localized: "Recent")
        }
    }

    var systemImageName: String {
        switch self {
        case .reading:
            return "book"
        case .favorites:
            return "star"
        case .recent:
            return "clock"
        }
    }

    var subtitle: String {
        switch self {
        case .reading:
            return String(localized: "Unread comics that have already been opened.")
        case .favorites:
            return String(localized: "Pinned comics stored in the library database.")
        case .recent:
            return String(localized: "Comics added in the last \(Self.defaultRecentDays) days.")
        }
    }

    func subtitleText(recentDays: Int = Self.defaultRecentDays) -> String {
        switch self {
        case .reading:
            return subtitle
        case .favorites:
            return subtitle
        case .recent:
            let dayCount = max(1, recentDays)
            return String(localized: "Comics added in the last \(dayCount) days.")
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .reading:
            return String(localized: "Nothing in Progress")
        case .favorites:
            return String(localized: "No Favorites Yet")
        case .recent:
            return String(localized: "No Recent Comics")
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .reading:
            return String(localized: "Open a comic and leave it unfinished to keep it here.")
        case .favorites:
            return String(localized: "Use the star button to add favorites.")
        case .recent:
            return String(localized: "Imported comics appear here automatically.")
        }
    }

    func emptyStateDescriptionText(recentDays: Int = Self.defaultRecentDays) -> String {
        switch self {
        case .reading:
            return emptyStateDescription
        case .favorites:
            return emptyStateDescription
        case .recent:
            let dayCount = max(1, recentDays)
            return String(localized: "Comics imported in the last \(dayCount) days will appear here automatically.")
        }
    }

    func summaryText(count: Int) -> String {
        switch self {
        case .reading:
            return String(localized: "Comics in progress: \(count)")
        case .favorites:
            return String(localized: "Favorite comics: \(count)")
        case .recent:
            return String(localized: "Recent comics: \(count)")
        }
    }

    func dashboardSubtitle(
        count: Int,
        recentDays: Int = Self.defaultRecentDays
    ) -> String {
        switch self {
        case .reading:
            return count == 1
                ? String(localized: "1 comic in progress.")
                : String(localized: "\(count) comics in progress.")
        case .favorites:
            return count == 1
                ? String(localized: "1 comic is pinned as favorite.")
                : String(localized: "\(count) comics are pinned as favorites.")
        case .recent:
            return count == 1
                ? String(localized: "1 comic added in the last \(recentDays) days.")
                : String(localized: "\(count) comics added in the last \(recentDays) days.")
        }
    }
}
