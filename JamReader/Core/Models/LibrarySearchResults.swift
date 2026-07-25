import Foundation

struct LibrarySearchResults: Equatable {
    let query: String
    let folders: [LibraryFolder]
    let comics: [LibraryComic]

    var isEmpty: Bool {
        folders.isEmpty && comics.isEmpty
    }

    var summaryText: String {
        let folderCount = folders.count
        let comicCount = comics.count
        let folderLabel = folderCount == 1
            ? String(localized: "1 folder")
            : String(localized: "\(folderCount) folders")
        let comicLabel = comicCount == 1
            ? String(localized: "1 comic")
            : String(localized: "\(comicCount) comics")
        return String(localized: "\(folderLabel) / \(comicLabel)")
    }
}
