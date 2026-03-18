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
            return "Reading"
        case .favorites:
            return "Favorites"
        case .recent:
            return "Recent"
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
            return "Unread comics that have already been opened."
        case .favorites:
            return "Pinned comics stored in the library database."
        case .recent:
            return "Comics added in the last \(Self.defaultRecentDays) days."
        }
    }

    func subtitleText(recentDays: Int = Self.defaultRecentDays) -> String {
        switch self {
        case .reading:
            return subtitle
        case .favorites:
            return subtitle
        case .recent:
            return "Comics added in the last \(max(1, recentDays)) days."
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .reading:
            return "Nothing in Progress"
        case .favorites:
            return "No Favorites Yet"
        case .recent:
            return "No Recent Comics"
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .reading:
            return "Open a comic and stop before finishing it to keep it in Reading."
        case .favorites:
            return "Use the star button in the reader to add comics to Favorites."
        case .recent:
            return "Recently imported comics will appear here automatically."
        }
    }

    func emptyStateDescriptionText(recentDays: Int = Self.defaultRecentDays) -> String {
        switch self {
        case .reading:
            return emptyStateDescription
        case .favorites:
            return emptyStateDescription
        case .recent:
            return "Comics imported in the last \(max(1, recentDays)) days will appear here automatically."
        }
    }

    var summaryFormat: String {
        switch self {
        case .reading:
            return "Comics in progress: %d"
        case .favorites:
            return "Favorite comics: %d"
        case .recent:
            return "Recent comics: %d"
        }
    }

    func summaryText(count: Int) -> String {
        String(format: summaryFormat, count)
    }

    func dashboardSubtitle(
        count: Int,
        recentDays: Int = Self.defaultRecentDays
    ) -> String {
        switch self {
        case .reading:
            return count == 1 ? "1 comic in progress." : "\(count) comics in progress."
        case .favorites:
            return count == 1 ? "1 comic is pinned as favorite." : "\(count) comics are pinned as favorites."
        case .recent:
            return count == 1
                ? "1 comic added in the last \(recentDays) days."
                : "\(count) comics added in the last \(recentDays) days."
        }
    }
}
