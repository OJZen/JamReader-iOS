import Foundation

enum LibraryKind: String, Codable, Hashable, CaseIterable {
    case appManaged
    case linkedFolder
    case importedComics

    var title: String {
        switch self {
        case .appManaged:
            return "App Managed"
        case .linkedFolder:
            return "Linked Folder"
        case .importedComics:
            return "Imported Comics"
        }
    }

    var isManagedByApp: Bool {
        self == .appManaged || self == .importedComics
    }
}
