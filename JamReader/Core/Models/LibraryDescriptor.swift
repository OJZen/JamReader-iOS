import Foundation

struct LibraryDescriptor: Identifiable, Codable, Hashable {
    static let defaultImportedComicsName = "Imported Comics"

    let id: UUID
    var kind: LibraryKind
    var name: String
    var rootPath: String
    var bookmarkData: Data
    var createdAt: Date
    var updatedAt: Date

    var sourcePath: String {
        get { rootPath }
        set { rootPath = newValue }
    }

    var sourceBookmarkData: Data {
        get { bookmarkData }
        set { bookmarkData = newValue }
    }

    var isImportedComics: Bool {
        kind == .importedComics
    }

    var displayName: String {
        guard isImportedComics, name == Self.defaultImportedComicsName else {
            return name
        }

        return String(localized: "Imported Comics")
    }
}
