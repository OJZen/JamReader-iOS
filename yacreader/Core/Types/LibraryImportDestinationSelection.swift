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
    let selection: LibraryImportDestinationSelection
    let title: String
    let subtitle: String
    let detail: String?

    var id: String {
        selection.id
    }
}
