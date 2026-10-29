import SwiftUI
import UIKit

/// Library type icon and tile color, shared by the library list, sidebar and
/// import destinations (see docs/design-system/components/Sidebar).
extension LibraryKind {
    var systemImageName: String {
        switch self {
        case .appManaged:
            return "books.vertical"
        case .linkedFolder:
            return Self.linkedFolderSystemImageName
        case .importedComics:
            return "tray"
        }
    }

    var tileColor: Color {
        switch self {
        case .appManaged:
            return .appJam
        case .linkedFolder:
            return .appOffline
        case .importedComics:
            return Color(.systemGray)
        }
    }

    /// `folder.badge.link` is missing from older SF Symbols releases.
    private static let linkedFolderSystemImageName = UIImage(systemName: "folder.badge.link") == nil
        ? "folder"
        : "folder.badge.link"
}

/// Collection entry colors only tell entries apart; names are always shown
/// (see docs/design-system/components/FolderAndCollection).
extension LibrarySpecialCollectionKind {
    var tint: Color {
        switch self {
        case .reading, .recent:
            return .appAccent
        case .favorites:
            return .appFavorite
        }
    }
}

extension LibraryOrganizationSectionKind {
    var tint: Color {
        switch self {
        case .labels:
            return .appOffline
        case .readingLists:
            return .appSuccess
        }
    }
}

extension LibrarySpecialCollectionKind {
    /// Collection entry symbols from the design system icon table.
    var collectionSystemImageName: String {
        switch self {
        case .reading:
            return "book"
        case .favorites:
            return "star.fill"
        case .recent:
            return "sparkles"
        }
    }
}

extension LibraryOrganizationSectionKind {
    var collectionSystemImageName: String {
        switch self {
        case .labels:
            return "tag"
        case .readingLists:
            return "list.bullet"
        }
    }
}
