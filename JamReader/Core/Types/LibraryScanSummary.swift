import Foundation

struct LibraryScanSummary: Codable, Equatable {
    let folderCount: Int
    let comicCount: Int
    let previousFolderCount: Int?
    let previousComicCount: Int?
    let reusedComicCount: Int?

    init(
        folderCount: Int,
        comicCount: Int,
        previousFolderCount: Int? = nil,
        previousComicCount: Int? = nil,
        reusedComicCount: Int? = nil
    ) {
        self.folderCount = folderCount
        self.comicCount = comicCount
        self.previousFolderCount = previousFolderCount
        self.previousComicCount = previousComicCount
        self.reusedComicCount = reusedComicCount
    }

    var summaryLine: String {
        "\(folderCount) folders · \(comicCount) comics"
    }

    var indexedSummaryLine: String {
        "Indexed \(summaryLine)"
    }

    var addedComicCount: Int? {
        guard let reusedComicCount else {
            return nil
        }

        return max(0, comicCount - reusedComicCount)
    }

    var removedComicCount: Int? {
        guard let previousComicCount, let reusedComicCount else {
            return nil
        }

        return max(0, previousComicCount - reusedComicCount)
    }

    var folderDelta: Int? {
        guard let previousFolderCount else {
            return nil
        }

        return folderCount - previousFolderCount
    }

    var changeSummaryLine: String? {
        var parts: [String] = []

        if let addedComicCount, addedComicCount > 0 {
            parts.append("Added \(addedComicCount) comics")
        }

        if let removedComicCount, removedComicCount > 0 {
            parts.append("Removed \(removedComicCount) comics")
        }

        if let folderDelta, folderDelta != 0 {
            let prefix = folderDelta > 0 ? "+" : "-"
            parts.append("\(prefix)\(abs(folderDelta)) folders")
        }

        if parts.isEmpty, previousComicCount != nil || previousFolderCount != nil {
            return "No content changes"
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var completionLine: String {
        if let changeSummaryLine {
            return "\(indexedSummaryLine) · \(changeSummaryLine)"
        }

        return indexedSummaryLine
    }
}
