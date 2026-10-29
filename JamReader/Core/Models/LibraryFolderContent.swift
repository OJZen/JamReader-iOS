import Foundation

struct LibraryFolderContent: Equatable {
    let folder: LibraryFolder
    let subfolders: [LibraryFolder]
    let comics: [LibraryComic]
    /// Folders from the library root down to the parent of `folder`.
    var ancestors: [LibraryFolder] = []

    var totalItemCount: Int {
        subfolders.count + comics.count
    }
}
