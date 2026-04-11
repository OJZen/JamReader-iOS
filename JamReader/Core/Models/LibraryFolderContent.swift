import Foundation

struct LibraryFolderContent: Equatable {
    let folder: LibraryFolder
    let subfolders: [LibraryFolder]
    let comics: [LibraryComic]

    var totalItemCount: Int {
        subfolders.count + comics.count
    }
}
