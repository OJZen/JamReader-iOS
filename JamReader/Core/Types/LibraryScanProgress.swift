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
            return String(localized: "Preparing Scan")
        case .scanningFolders:
            return String(localized: "Scanning Folders")
        case .scanningComics:
            return String(localized: "Scanning Comics")
        case .importingMetadata:
            return String(localized: "Importing ComicInfo")
        case .finalizing:
            return String(localized: "Finalizing Library")
        }
    }

    var countsLine: String {
        String(localized: "\(processedFolderCount) folders · \(processedComicCount) comics")
    }

    var detailLine: String {
        guard let currentPath,
              !currentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return countsLine
        }

        return String(localized: "\(countsLine) · \(currentPath)")
    }
}
