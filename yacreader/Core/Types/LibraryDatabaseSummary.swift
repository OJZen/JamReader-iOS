import Foundation

struct LibraryDatabaseSummary: Equatable {
    var exists: Bool
    var version: String?
    var folderCount: Int
    var comicCount: Int
    var lastError: String?

    init(
        exists: Bool = false,
        version: String? = nil,
        folderCount: Int = 0,
        comicCount: Int = 0,
        lastError: String? = nil
    ) {
        self.exists = exists
        self.version = version
        self.folderCount = folderCount
        self.comicCount = comicCount
        self.lastError = lastError
    }

    var summaryLine: String {
        if !exists {
            return "No library database detected yet."
        }

        let versionText = version ?? "Unknown"
        return "DB \(versionText) · \(folderCount) folders · \(comicCount) comics"
    }
}
