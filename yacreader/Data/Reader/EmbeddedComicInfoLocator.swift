import Foundation

enum EmbeddedComicInfoLocator {
    nonisolated static func preferredPath(in entryPaths: [String]) -> String? {
        let xmlPaths = entryPaths.filter { $0.lowercased().hasSuffix(".xml") }
        guard !xmlPaths.isEmpty else {
            return nil
        }

        if let comicInfoPath = xmlPaths.first(where: isComicInfoPath(_:)) {
            return comicInfoPath
        }

        return xmlPaths.first
    }

    nonisolated private static func isComicInfoPath(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame
    }
}
