import Foundation
import CryptoKit

final class LibraryCoverLocator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func coverURL(for comic: LibraryComic, metadataRootURL: URL) -> URL? {
        let coverURL = plannedCoverURL(for: comic, metadataRootURL: metadataRootURL)

        return fileManager.fileExists(atPath: coverURL.path) ? coverURL : nil
    }

    func plannedCoverURL(for comic: LibraryComic, metadataRootURL: URL) -> URL {
        metadataRootURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(Self.coverAssetKey(for: comic)).jpg")
    }

    func plannedCoverURL(assetKey: String, metadataRootURL: URL) -> URL {
        metadataRootURL
            .appendingPathComponent("covers", isDirectory: true)
            .appendingPathComponent("\(assetKey).jpg")
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

    func previewCoverURLs(for folder: LibraryFolder, metadataRootURL: URL) -> [URL] {
        folder.previewCoverAssetKeys.compactMap { assetKey in
            let coverURL = plannedCoverURL(assetKey: assetKey, metadataRootURL: metadataRootURL)
            return fileManager.fileExists(atPath: coverURL.path) ? coverURL : nil
        }
    }

    static func coverAssetKey(for comic: LibraryComic) -> String {
        coverAssetKey(
            forRelativePath: normalizedRelativePath(
                comic.path,
                fallbackFileName: comic.fileName
            )
        )
    }

    static func coverAssetKey(forRelativePath relativePath: String) -> String {
        let normalizedPath = relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedRelativePath(
        _ path: String?,
        fallbackFileName: String
    ) -> String {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = trimmed.isEmpty ? fallbackFileName : trimmed
        let normalized = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized.isEmpty ? fallbackFileName : normalized
    }
}
