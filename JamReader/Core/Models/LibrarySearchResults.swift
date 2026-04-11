import Foundation

struct LibrarySearchResults: Equatable {
    let query: String
    let folders: [LibraryFolder]
    let comics: [LibraryComic]

    var isEmpty: Bool {
        folders.isEmpty && comics.isEmpty
    }

    var summaryText: String {
        let folderLabel = folders.count == 1 ? "1 folder" : "\(folders.count) folders"
        let comicLabel = comics.count == 1 ? "1 comic" : "\(comics.count) comics"
        return "\(folderLabel) / \(comicLabel)"
    }
}
