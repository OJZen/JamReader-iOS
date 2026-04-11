import Foundation

enum RemoteDirectorySortMode: String, CaseIterable, Identifiable {
    case nameAscending
    case recentlyUpdated
    case largestFirst

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .nameAscending:
            return "Name"
        case .recentlyUpdated:
            return "Recently Updated"
        case .largestFirst:
            return "Largest First"
        }
    }

    var shortTitle: String {
        switch self {
        case .nameAscending:
            return "Name"
        case .recentlyUpdated:
            return "Recent"
        case .largestFirst:
            return "Largest"
        }
    }

    var systemImageName: String {
        switch self {
        case .nameAscending:
            return "textformat"
        case .recentlyUpdated:
            return "clock.arrow.circlepath"
        case .largestFirst:
            return "arrow.up.forward.and.arrow.down.backward"
        }
    }
}

extension Array where Element == RemoteDirectoryItem {
    func sorted(using mode: RemoteDirectorySortMode) -> [RemoteDirectoryItem] {
        sorted { lhs, rhs in
            switch mode {
            case .nameAscending:
                return compareByName(lhs, rhs) < 0
            case .recentlyUpdated:
                return compareOptional(
                    lhs.modifiedAt,
                    rhs.modifiedAt,
                    fallback: { compareByName(lhs, rhs) }
                ) < 0
            case .largestFirst:
                return compareOptional(
                    lhs.fileSize,
                    rhs.fileSize,
                    fallback: { compareByName(lhs, rhs) }
                ) < 0
            }
        }
    }

    private func compareByName(_ lhs: RemoteDirectoryItem, _ rhs: RemoteDirectoryItem) -> Int {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending:
            return -1
        case .orderedDescending:
            return 1
        case .orderedSame:
            return 0
        }
    }

    private func compareOptional<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        fallback: () -> Int
    ) -> Int {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs ? -1 : 1
        case (_?, nil):
            return -1
        case (nil, _?):
            return 1
        default:
            return fallback()
        }
    }
}
