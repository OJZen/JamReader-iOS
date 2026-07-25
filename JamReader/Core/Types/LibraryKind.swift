import Foundation

enum LibraryKind: String, Codable, Hashable, CaseIterable {
    case appManaged
    case linkedFolder
    case importedComics

    var title: String {
        switch self {
        case .appManaged:
            return String(localized: "App Managed")
        case .linkedFolder:
            return String(localized: "Linked Folder")
        case .importedComics:
            return String(localized: "Imported Comics")
        }
    }

    var isManagedByApp: Bool {
        self == .appManaged || self == .importedComics
    }
}
