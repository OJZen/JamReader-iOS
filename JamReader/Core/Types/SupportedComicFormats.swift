import Foundation

enum SupportedComicFormats {
    nonisolated static let archiveFileExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt"
    ]

    nonisolated static let documentFileExtensions: Set<String> = [
        "pdf", "epub"
    ]

    nonisolated static let eBookFileExtensions: Set<String> = [
        "epub"
    ]

    nonisolated static let muPDFDocumentFileExtensions: Set<String> = [
        "pdf", "epub"
    ]

    nonisolated static let comicFileExtensions: Set<String> = archiveFileExtensions
        .union(documentFileExtensions)

    nonisolated static func supportsComicFileExtension(_ fileExtension: String) -> Bool {
        comicFileExtensions.contains(normalizedExtension(fileExtension))
    }

    nonisolated static func supportsComicFile(named fileName: String) -> Bool {
        supportsComicFileExtension(URL(fileURLWithPath: fileName).pathExtension)
    }

    nonisolated static func isArchiveFileExtension(_ fileExtension: String) -> Bool {
        archiveFileExtensions.contains(normalizedExtension(fileExtension))
    }

    nonisolated static func displayName(forFileExtension fileExtension: String) -> String {
        let normalizedExtension = normalizedExtension(fileExtension)
        switch normalizedExtension {
        case "cbz":
            return "CBZ (ZIP)"
        case "zip":
            return "ZIP"
        case "cbr":
            return "CBR (RAR)"
        case "rar":
            return "RAR"
        case "cb7":
            return "CB7 (7Z)"
        case "7z":
            return "7Z"
        case "cbt":
            return "CBT (TAR)"
        case "tar":
            return "TAR"
        case "pdf":
            return "PDF"
        case "epub":
            return "EPUB"
        default:
            return normalizedExtension.isEmpty ? String(localized: "Comic File") : normalizedExtension.uppercased()
        }
    }

    nonisolated private static func normalizedExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
