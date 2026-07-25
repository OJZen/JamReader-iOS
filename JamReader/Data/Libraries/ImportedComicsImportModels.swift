import Foundation

struct ImportedComicsImportResult {
    let importedDestinationID: UUID
    let importedDestinationName: String
    let importedDestinationDisplayName: String
    let createdLibrary: Bool
    let importedComicCount: Int
    let scanSummary: LibraryScanSummary?
    let scanErrorMessage: String?
    let unsupportedItemNames: [String]
    let failedItemNames: [String]

    var hasImportedAnyComics: Bool {
        importedComicCount > 0
    }

    func completionMessageLines(extraFailedItemNames: [String] = []) -> [String] {
        var messageLines: [String] = []

        if createdLibrary {
            messageLines.append(String(localized: "Added \(importedDestinationDisplayName)."))
        }

        if importedComicCount > 0 {
            if importedComicCount == 1 {
                messageLines.append(String(localized: "Imported 1 comic file into \(importedDestinationDisplayName)."))
            } else {
                messageLines.append(String(localized: "Imported \(importedComicCount) comic files into \(importedDestinationDisplayName)."))
            }
        }

        if let scanSummary {
            messageLines.append(scanSummary.indexedSummaryLine + ".")
        } else if let scanErrorMessage {
            messageLines.append(String(localized: "Automatic indexing failed: \(scanErrorMessage)"))
            messageLines.append(String(localized: "Open \(importedDestinationDisplayName) and run Refresh to index the new files."))
        }

        if !unsupportedItemNames.isEmpty {
            let unsupportedCount = unsupportedItemNames.count
            if unsupportedCount == 1 {
                messageLines.append(String(localized: "Skipped 1 unsupported item."))
            } else {
                messageLines.append(String(localized: "Skipped \(unsupportedCount) unsupported items."))
            }
        }

        let combinedFailedItemNames = failedItemNames + extraFailedItemNames
        if !combinedFailedItemNames.isEmpty {
            let preview = NamePreviewFormatter.preview(from: combinedFailedItemNames)
            let failedCount = combinedFailedItemNames.count
            messageLines.append(String(localized: "Failed to import \(failedCount) item(s): \(preview)."))
        }

        return messageLines
    }
}

struct ImportedComicsImportProgress {
    enum Phase: Equatable {
        case transferring
        case indexing
    }

    let phase: Phase
    let completedCount: Int
    let totalCount: Int?
    let currentItemName: String?
    let scanProgress: LibraryScanProgress?

    var fractionCompleted: Double? {
        guard let totalCount, totalCount > 0 else {
            return nil
        }

        return min(1, max(0, Double(completedCount) / Double(totalCount)))
    }

    var title: String {
        switch phase {
        case .transferring:
            return String(localized: "Importing Comics")
        case .indexing:
            return String(localized: "Indexing Comics")
        }
    }

    var detailLine: String? {
        if let scanProgress {
            return scanProgress.detailLine
        }

        if let currentItemName, !currentItemName.isEmpty {
            return currentItemName
        }

        if let totalCount {
            return String(localized: "\(completedCount) of \(totalCount)")
        }

        return nil
    }
}

nonisolated final class LibraryImportCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func checkCancelled() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()

        if cancelled {
            throw CancellationError()
        }
    }
}
