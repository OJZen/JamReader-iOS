import Foundation

enum ComicInfoImportPolicy: String, CaseIterable, Codable, Hashable, Identifiable {
    case fillMissing
    case overwriteExisting

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fillMissing:
            return "Fill Empty Fields"
        case .overwriteExisting:
            return "Overwrite Existing Fields"
        }
    }

    var summaryText: String {
        switch self {
        case .fillMissing:
            return "Only applies XML values where the library field is still empty."
        case .overwriteExisting:
            return "Replaces current library values with embedded ComicInfo.xml values."
        }
    }
}
