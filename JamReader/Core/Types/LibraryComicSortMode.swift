import Foundation

enum LibraryComicSortMode: String, CaseIterable, Identifiable {
    case sourceOrder
    case titleAscending
    case titleDescending
    case fileNameAscending
    case recentlyOpened
    case recentlyAdded

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sourceOrder:
            return "Default Order"
        case .titleAscending:
            return "Title A-Z"
        case .titleDescending:
            return "Title Z-A"
        case .fileNameAscending:
            return "File Name"
        case .recentlyOpened:
            return "Recently Opened"
        case .recentlyAdded:
            return "Recently Added"
        }
    }
}

extension Array where Element == LibraryComic {
    func sorted(using mode: LibraryComicSortMode) -> [LibraryComic] {
        switch mode {
        case .sourceOrder:
            return self
        case .titleAscending:
            return sorted { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: {
                    localizedComparison($0.displayTitle, $1.displayTitle)
                })
            }
        case .titleDescending:
            return sorted { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: {
                    localizedComparison($1.displayTitle, $0.displayTitle)
                })
            }
        case .fileNameAscending:
            return sorted { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: {
                    localizedComparison($0.fileName, $1.fileName)
                })
            }
        case .recentlyOpened:
            return sorted { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: {
                    dateComparison($0.lastOpenedAt, $1.lastOpenedAt)
                })
            }
        case .recentlyAdded:
            return sorted { lhs, rhs in
                compare(lhs: lhs, rhs: rhs, primary: {
                    dateComparison($0.addedAt, $1.addedAt)
                })
            }
        }
    }

    private func compare(
        lhs: LibraryComic,
        rhs: LibraryComic,
        primary: (LibraryComic, LibraryComic) -> ComparisonResult
    ) -> Bool {
        let primaryResult = primary(lhs, rhs)
        if primaryResult != .orderedSame {
            return primaryResult == .orderedAscending
        }

        return tieBreak(lhs: lhs, rhs: rhs) == .orderedAscending
    }

    private func localizedComparison(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    private func dateComparison(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left != right {
                return left > right ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return .orderedSame
        }
    }

    private func tieBreak(lhs: LibraryComic, rhs: LibraryComic) -> ComparisonResult {
        let titleResult = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
        if titleResult != .orderedSame {
            return titleResult
        }

        let fileNameResult = lhs.fileName.localizedStandardCompare(rhs.fileName)
        if fileNameResult != .orderedSame {
            return fileNameResult
        }

        if lhs.id != rhs.id {
            return lhs.id < rhs.id ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }
}
