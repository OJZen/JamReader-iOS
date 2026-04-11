import Foundation

enum LibraryImportDestinationSelection: Hashable, Identifiable {
    case importedComics
    case library(UUID)

    var id: String {
        storageValue
    }

    var storageValue: String {
        switch self {
        case .importedComics:
            return "importedComics"
        case .library(let libraryID):
            return "library:\(libraryID.uuidString)"
        }
    }

    init?(storageValue: String) {
        if storageValue == "importedComics" {
            self = .importedComics
            return
        }

        guard storageValue.hasPrefix("library:") else {
            return nil
        }

        let rawIdentifier = String(storageValue.dropFirst("library:".count))
        guard let libraryID = UUID(uuidString: rawIdentifier) else {
            return nil
        }

        self = .library(libraryID)
    }
}

struct LibraryImportDestinationOption: Identifiable, Hashable {
    enum Availability: Hashable {
        case available
        case unavailable(String)

        var isSelectable: Bool {
            if case .available = self {
                return true
            }

            return false
        }
    }

    enum Status: Hashable {
        case appManaged
        case linkedFolder
        case readOnly

        var title: String {
            switch self {
            case .appManaged:
                return "App Managed"
            case .linkedFolder:
                return "Linked Folder"
            case .readOnly:
                return "Read-Only"
            }
        }
    }

    let selection: LibraryImportDestinationSelection
    let title: String
    let status: Status?
    let detail: String?
    let availability: Availability

    var id: String {
        selection.id
    }

    var isSelectable: Bool {
        availability.isSelectable
    }
}
