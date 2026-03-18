import Foundation

final class LibraryCoverLocator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func coverURL(for comic: LibraryComic, metadataRootURL: URL) -> URL? {
        let coverURL = metadataRootURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(comic.hash).jpg")

        return fileManager.fileExists(atPath: coverURL.path) ? coverURL : nil
    }

    func coverURL(for folder: LibraryFolder, metadataRootURL: URL) -> URL? {
        let customFolderCoverURL = metadataRootURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("folders", isDirectory: true)
            .appendingPathComponent("\(folder.id).jpg")

        if fileManager.fileExists(atPath: customFolderCoverURL.path) {
            return customFolderCoverURL
        }

        guard let firstChildHash = folder.firstChildHash, !firstChildHash.isEmpty else {
            return nil
        }

        let fallbackCoverURL = metadataRootURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(firstChildHash).jpg")

        return fileManager.fileExists(atPath: fallbackCoverURL.path) ? fallbackCoverURL : nil
    }
}
