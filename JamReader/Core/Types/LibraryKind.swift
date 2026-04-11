import Foundation

enum LibraryKind: String, Codable, Hashable, CaseIterable {
    case linkedFolder
    case importedComics

    var title: String {
        switch self {
        case .linkedFolder:
            return "Linked Folder"
        case .importedComics:
            return "Imported Comics"
        }
    }

    var isManagedByApp: Bool {
        self == .importedComics
    }
}
