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
            return String(localized: "Fill Empty Fields")
        case .overwriteExisting:
            return String(localized: "Overwrite Existing Fields")
        }
    }

    var summaryText: String {
        switch self {
        case .fillMissing:
            return String(localized: "Only applies XML values where the library field is still empty.")
        case .overwriteExisting:
            return String(localized: "Replaces current library values with embedded ComicInfo.xml values.")
        }
    }
}
