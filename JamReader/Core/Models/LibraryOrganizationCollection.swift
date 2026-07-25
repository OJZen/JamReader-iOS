import Foundation

enum LibraryOrganizationCollectionType: String, Hashable {
    case label
    case readingList
}

enum LibraryOrganizationSectionKind: String, CaseIterable, Identifiable, Hashable {
    case labels
    case readingLists

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .labels:
            return String(localized: "Tags")
        case .readingLists:
            return String(localized: "Reading Lists")
        }
    }

    var navigationTitle: String {
        title
    }

    var systemImageName: String {
        switch self {
        case .labels:
            return "tag"
        case .readingLists:
            return "text.badge.plus"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .labels:
            return String(localized: "No Tags Yet")
        case .readingLists:
            return String(localized: "No Reading Lists Yet")
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .labels:
            return String(localized: "Create tags to group comics.")
        case .readingLists:
            return String(localized: "Create reading lists for custom queues.")
        }
    }

    var createActionTitle: String {
        switch self {
        case .labels:
            return String(localized: "New Tag")
        case .readingLists:
            return String(localized: "New Reading List")
        }
    }

    var createNamePrompt: String {
        switch self {
        case .labels:
            return String(localized: "Tag name")
        case .readingLists:
            return String(localized: "Reading list name")
        }
    }

    var detailEmptyStateTitle: String {
        switch self {
        case .labels:
            return String(localized: "This Tag Is Empty")
        case .readingLists:
            return String(localized: "This Reading List Is Empty")
        }
    }

    var detailEmptyStateDescription: String {
        switch self {
        case .labels:
            return String(localized: "Add comics to use this tag.")
        case .readingLists:
            return String(localized: "Add comics to build this reading list.")
        }
    }

    var collectionType: LibraryOrganizationCollectionType {
        switch self {
        case .labels:
            return .label
        case .readingLists:
            return .readingList
        }
    }

    func summaryText(count: Int) -> String {
        switch self {
        case .labels:
            return count == 1
                ? String(localized: "1 tag available")
                : String(localized: "\(count) tags available")
        case .readingLists:
            return count == 1
                ? String(localized: "1 reading list available")
                : String(localized: "\(count) reading lists available")
        }
    }
}

struct LibraryOrganizationCollection: Identifiable, Hashable {
    let id: Int64
    let name: String
    let type: LibraryOrganizationCollectionType
    let comicCount: Int
    let isAssigned: Bool
    let labelColor: LibraryLabelColor?

    var displayTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        switch type {
        case .label:
            return String(localized: "Untitled Tag")
        case .readingList:
            return String(localized: "Untitled Reading List")
        }
    }

    var sectionKind: LibraryOrganizationSectionKind {
        switch type {
        case .label:
            return .labels
        case .readingList:
            return .readingLists
        }
    }

    var systemImageName: String {
        switch type {
        case .label:
            return "tag.fill"
        case .readingList:
            return "text.badge.plus"
        }
    }

    var countText: String {
        comicCount == 1
            ? String(localized: "1 comic")
            : String(localized: "\(comicCount) comics")
    }

    func updatingDetails(
        name: String? = nil,
        labelColor: LibraryLabelColor? = nil
    ) -> LibraryOrganizationCollection {
        LibraryOrganizationCollection(
            id: id,
            name: name ?? self.name,
            type: type,
            comicCount: comicCount,
            isAssigned: isAssigned,
            labelColor: type == .label ? (labelColor ?? self.labelColor) : nil
        )
    }

    func updatingAssignment(_ isAssigned: Bool) -> LibraryOrganizationCollection {
        let countDelta = isAssigned == self.isAssigned ? 0 : (isAssigned ? 1 : -1)

        return LibraryOrganizationCollection(
            id: id,
            name: name,
            type: type,
            comicCount: max(0, comicCount + countDelta),
            isAssigned: isAssigned,
            labelColor: labelColor
        )
    }
}

struct LibraryOrganizationSnapshot: Hashable {
    var labels: [LibraryOrganizationCollection]
    var readingLists: [LibraryOrganizationCollection]

    static let empty = LibraryOrganizationSnapshot(labels: [], readingLists: [])

    var isEmpty: Bool {
        labels.isEmpty && readingLists.isEmpty
    }

    func collections(for sectionKind: LibraryOrganizationSectionKind) -> [LibraryOrganizationCollection] {
        switch sectionKind {
        case .labels:
            return labels
        case .readingLists:
            return readingLists
        }
    }

    mutating func update(_ collection: LibraryOrganizationCollection) {
        switch collection.type {
        case .label:
            if let index = labels.firstIndex(where: { $0.id == collection.id }) {
                labels[index] = collection
            }
        case .readingList:
            if let index = readingLists.firstIndex(where: { $0.id == collection.id }) {
                readingLists[index] = collection
            }
        }
    }
}
