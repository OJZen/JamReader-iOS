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

        if let compatibilityIssueDescription {
            return compatibilityIssueDescription
        }

        let versionText = version ?? "Unknown"
        return "DB \(versionText) · \(folderCount) folders · \(comicCount) comics"
    }

    var hasCompatibleSchemaVersion: Bool {
        guard exists else {
            return true
        }

        return LibraryDatabaseBootstrapper.supportsDatabaseVersion(version)
    }

    var compatibilityIssueDescription: String? {
        guard exists, !hasCompatibleSchemaVersion else {
            return nil
        }

        if let lastError {
            return lastError
        }

        if let version {
            return "DB \(version) is not supported on this iOS build."
        }

        return "The library database schema could not be verified on this iOS build."
    }
}
