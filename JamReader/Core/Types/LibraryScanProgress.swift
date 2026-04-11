import Foundation

enum LibraryScanPhase: Equatable {
    case preparing
    case scanningFolders
    case scanningComics
    case importingMetadata
    case finalizing
}

struct LibraryScanProgress: Equatable {
    let phase: LibraryScanPhase
    let currentPath: String?
    let processedFolderCount: Int
    let processedComicCount: Int

    var title: String {
        switch phase {
        case .preparing:
            return "Preparing Scan"
        case .scanningFolders:
            return "Scanning Folders"
        case .scanningComics:
            return "Scanning Comics"
        case .importingMetadata:
            return "Importing ComicInfo"
        case .finalizing:
            return "Finalizing Library"
        }
    }

    var countsLine: String {
        "\(processedFolderCount) folders · \(processedComicCount) comics"
    }

    var detailLine: String {
        guard let currentPath,
              !currentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return countsLine
        }

        return "\(countsLine) · \(currentPath)"
    }
}
