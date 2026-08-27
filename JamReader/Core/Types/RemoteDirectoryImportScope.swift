import Foundation

enum RemoteDirectoryImportScope: String, CaseIterable, Hashable, Identifiable {
    case visibleResults
    case currentFolderOnly
    case includeSubfolders

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .visibleResults:
            return String(localized: "Visible Comics Only")
        case .currentFolderOnly:
            return String(localized: "This Folder Only")
        case .includeSubfolders:
            return String(localized: "Include Subfolders")
        }
    }

    var summaryText: String {
        switch self {
        case .visibleResults:
            return String(localized: "Only comics shown here.")
        case .currentFolderOnly:
            return String(localized: "Comics directly in this folder.")
        case .includeSubfolders:
            return String(localized: "This folder and nested folders.")
        }
    }
}
