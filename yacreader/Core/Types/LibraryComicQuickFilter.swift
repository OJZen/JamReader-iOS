import Foundation

enum LibraryComicQuickFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case favorites
    case bookmarked

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .unread:
            return "Unread"
        case .favorites:
            return "Favorites"
        case .bookmarked:
            return "Bookmarked"
        }
    }

    var systemImageName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .unread:
            return "book.closed"
        case .favorites:
            return "star"
        case .bookmarked:
            return "bookmark"
        }
    }

    func matches(_ comic: LibraryComic) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return !comic.read
        case .favorites:
            return comic.isFavorite
        case .bookmarked:
            return !comic.bookmarkPageIndices.isEmpty
        }
    }
}

extension LibraryComic {
    func matchesSearchQuery(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        let candidates = [
            displayTitle,
            subtitle,
            fileName,
            series ?? "",
            volume ?? "",
            issueLabel ?? "",
            path ?? ""
        ]

        return candidates.contains { candidate in
            candidate.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

extension LibraryFolder {
    func matchesSearchQuery(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        let candidates = [
            displayName,
            name,
            path
        ]

        return candidates.contains { candidate in
            candidate.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}
