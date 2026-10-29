import Foundation

/// Quick filters for the comics in one folder or collection: All, Unread,
/// In Progress, Read and With Bookmarks. In Progress is the in-library
/// continue reading.
enum LibraryComicQuickFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case reading
    case read
    case bookmarked

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All")
        case .unread:
            return String(localized: "Unread")
        case .reading:
            return String(localized: "In Progress")
        case .read:
            return String(localized: "Read")
        case .bookmarked:
            return String(localized: "With Bookmarks")
        }
    }

    func matches(_ comic: LibraryComic) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return !comic.read && !comic.isInProgress
        case .reading:
            return comic.isInProgress
        case .read:
            return comic.read
        case .bookmarked:
            return !comic.bookmarkPageIndices.isEmpty
        }
    }
}

extension LibraryComic {
    /// Opened and not finished, the same rule as Continue Reading.
    var isInProgress: Bool {
        !read && hasBeenOpened
    }

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
