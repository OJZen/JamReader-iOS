import CryptoKit
import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

enum LibraryScannerError: LocalizedError {
    case sqliteUnavailable
    case databaseMissing
    case incompatibleDatabaseVersion(String)
    case openDatabaseFailed(String)
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .databaseMissing:
            return "The library database must exist before scanning."
        case .incompatibleDatabaseVersion(let reason):
            return reason
        case .openDatabaseFailed(let reason):
            return "Unable to open the library database for scanning. \(reason)"
        case .scanFailed(let reason):
            return "Library scan failed. \(reason)"
        }
    }
}

final class LibraryScanner {
    private let fileManager: FileManager
    private let metadataExtractor: LibraryComicMetadataExtractor
    private let supportedExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf"
    ]

    init(
        fileManager: FileManager = .default,
        metadataExtractor: LibraryComicMetadataExtractor = LibraryComicMetadataExtractor()
    ) {
        self.fileManager = fileManager
        self.metadataExtractor = metadataExtractor
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        try performScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            mode: .initial,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func rescanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        try performScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            mode: .rebuildPreservingComicRelationships,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func refreshFolder(
        sourceRootURL: URL,
        databaseURL: URL,
        folder: LibraryFolder,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        try performSubtreeRefresh(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            folder: folder,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func appendImportedComics(
        sourceRootURL: URL,
        databaseURL: URL,
        fileURLs: [URL],
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        #if canImport(SQLite3)
        try cancellationCheck?()
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryScannerError.databaseMissing
        }

        let summary = SQLiteDatabaseInspector().inspectDatabase(at: databaseURL)
        guard summary.hasCompatibleSchemaVersion else {
            let versionText = summary.version ?? "Unknown"
            throw LibraryScannerError.incompatibleDatabaseVersion(
                "This library uses DB \(versionText), which is not supported for scanning on this iOS build."
            )
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryScannerError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        try execute("PRAGMA foreign_keys = ON;", database: database)
        try execute("BEGIN TRANSACTION;", database: database)

        do {
            try cancellationCheck?()
            let normalizedRootURL = sourceRootURL.standardizedFileURL
            let importedRelativePaths = Array(
                Set(
                    fileURLs
                        .map(\.standardizedFileURL)
                        .filter { $0.path.hasPrefix(normalizedRootURL.path) }
                        .map { makeRelativePath(for: $0, sourceRootURL: normalizedRootURL) }
                )
            )
            try pruneMissingComicRows(
                sourceRootURL: normalizedRootURL,
                database: database
            )
            try collapseDuplicateComicRows(
                forRelativePaths: importedRelativePaths,
                database: database
            )
            var indexedRelativePaths = try loadExistingComicPaths(database: database)
            let previousFolderCount = try loadIndexedFolderCount(database: database)
            let previousComicCount = try loadIndexedComicCount(database: database)

            progressHandler?(
                LibraryScanProgress(
                    phase: .preparing,
                    currentPath: "/",
                    processedFolderCount: 0,
                    processedComicCount: 0
                )
            )

            var appendedComicCount = 0
            var seenFilePaths = Set<String>()
            let sortedFileURLs = fileURLs
                .map(\.standardizedFileURL)
                .filter { seenFilePaths.insert($0.path).inserted }
                .sorted { lhs, rhs in
                    lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }

            for fileURL in sortedFileURLs {
                try cancellationCheck?()
                try autoreleasepool {
                    guard fileManager.fileExists(atPath: fileURL.path),
                          isSupportedComicFile(fileURL) else {
                        return
                    }

                    let relativePath = makeRelativePath(for: fileURL, sourceRootURL: normalizedRootURL)
                    guard !indexedRelativePaths.contains(relativePath) else {
                        return
                    }
                    try appendImportedComic(
                        fileURL: fileURL,
                        relativePath: relativePath,
                        parentFolderID: 1,
                        database: database
                    )
                    indexedRelativePaths.insert(relativePath)
                    appendedComicCount += 1

                    if appendedComicCount == 1 || appendedComicCount.isMultiple(of: 5) {
                        progressHandler?(
                            LibraryScanProgress(
                                phase: .scanningComics,
                                currentPath: relativePath,
                                processedFolderCount: 0,
                                processedComicCount: appendedComicCount
                            )
                        )
                    }
                }
            }

            progressHandler?(
                LibraryScanProgress(
                    phase: .finalizing,
                    currentPath: "/",
                    processedFolderCount: 0,
                    processedComicCount: appendedComicCount
                )
            )

            _ = try refreshFolderMetadata(folderID: 1, database: database)
            try execute("COMMIT;", database: database)

            return LibraryScanSummary(
                folderCount: previousFolderCount,
                comicCount: previousComicCount + appendedComicCount,
                previousFolderCount: previousFolderCount,
                previousComicCount: previousComicCount,
                reusedComicCount: previousComicCount
            )
        } catch {
            _ = try? execute("ROLLBACK;", database: database)
            throw error
        }
        #else
        throw LibraryScannerError.sqliteUnavailable
        #endif
    }

    #if canImport(SQLite3)
    private enum ScanMode {
        case initial
        case rebuildPreservingComicRelationships
    }

    private struct ExistingComicRecord {
        let comicID: Int64
        let comicInfoID: Int64
        let hash: String
        let relativePath: String?
    }

    private struct ComicInfoResolution {
        let id: Int64
        let isNew: Bool
    }

    private struct LabelMembershipSnapshot {
        let labelID: Int64
        let comicID: Int64
        let ordering: Int64?
    }

    private struct ReadingListMembershipSnapshot {
        let readingListID: Int64
        let comicID: Int64
        let ordering: Int64?
    }

    private struct DefaultReadingListMembershipSnapshot {
        let defaultReadingListID: Int64
        let comicID: Int64
        let ordering: Int64?
    }

    private struct RescanSnapshot {
        let existingFolderCount: Int
        let existingComicCount: Int
        let comicsByPath: [String: ExistingComicRecord]
        let comicsByHash: [String: [ExistingComicRecord]]
        let labelMemberships: [LabelMembershipSnapshot]
        let readingListMemberships: [ReadingListMembershipSnapshot]
        let defaultReadingListMemberships: [DefaultReadingListMembershipSnapshot]

        static let empty = RescanSnapshot(
            existingFolderCount: 0,
            existingComicCount: 0,
            comicsByPath: [:],
            comicsByHash: [:],
            labelMemberships: [],
            readingListMemberships: [],
            defaultReadingListMemberships: []
        )
    }

    private final class ScanContext {
        let sourceRootURL: URL
        let coversRootURL: URL
        let reusableComicsByPath: [String: ExistingComicRecord]
        let reusableComicsByHash: [String: [ExistingComicRecord]]
        let progressHandler: ((LibraryScanProgress) -> Void)?

        var consumedReusableComicIDs = Set<Int64>()
        var insertedComicIDs = Set<Int64>()
        var summary = LibraryScanSummary(folderCount: 0, comicCount: 0)
        var lastReportedComicCount = 0

        init(
            sourceRootURL: URL,
            coversRootURL: URL,
            snapshot: RescanSnapshot,
            progressHandler: ((LibraryScanProgress) -> Void)?
        ) {
            self.sourceRootURL = sourceRootURL
            self.coversRootURL = coversRootURL
            self.reusableComicsByPath = snapshot.comicsByPath
            self.reusableComicsByHash = snapshot.comicsByHash
            self.progressHandler = progressHandler
        }

        func report(_ phase: LibraryScanPhase, currentPath: String?) {
            progressHandler?(
                LibraryScanProgress(
                    phase: phase,
                    currentPath: currentPath,
                    processedFolderCount: summary.folderCount,
                    processedComicCount: summary.comicCount
                )
            )
        }

        func reportComicProgressIfNeeded(currentPath: String?) {
            guard summary.comicCount == 1 || summary.comicCount - lastReportedComicCount >= 5 else {
                return
            }

            lastReportedComicCount = summary.comicCount
            report(.scanningComics, currentPath: currentPath)
        }
    }

    private func performScan(
        sourceRootURL: URL,
        databaseURL: URL,
        mode: ScanMode,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        try cancellationCheck?()
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryScannerError.databaseMissing
        }

        let summary = SQLiteDatabaseInspector().inspectDatabase(at: databaseURL)
        guard summary.hasCompatibleSchemaVersion else {
            let versionText = summary.version ?? "Unknown"
            throw LibraryScannerError.incompatibleDatabaseVersion(
                "This library uses DB \(versionText), which is not supported for scanning on this iOS build."
            )
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryScannerError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        try execute("PRAGMA foreign_keys = ON;", database: database)
        try execute("BEGIN TRANSACTION;", database: database)

        do {
            try cancellationCheck?()
            progressHandler?(
                LibraryScanProgress(
                    phase: .preparing,
                    currentPath: "/",
                    processedFolderCount: 0,
                    processedComicCount: 0
                )
            )

            let coversRootURL = databaseURL
                .deletingLastPathComponent()
                .appendingPathComponent("covers", isDirectory: true)

            let snapshot: RescanSnapshot
            switch mode {
            case .initial:
                snapshot = .empty
            case .rebuildPreservingComicRelationships:
                snapshot = try makeRescanSnapshot(database: database)
                try clearIndexedLibraryStructure(database: database)
            }

            let context = ScanContext(
                sourceRootURL: sourceRootURL,
                coversRootURL: coversRootURL,
                snapshot: snapshot,
                progressHandler: progressHandler
            )

            try scanDirectory(
                at: sourceRootURL,
                parentFolderID: 1,
                database: database,
                context: context,
                cancellationCheck: cancellationCheck
            )

            if case .rebuildPreservingComicRelationships = mode {
                try cancellationCheck?()
                try restoreMemberships(
                    snapshot: snapshot,
                    survivingComicIDs: context.insertedComicIDs,
                    database: database
                )
            }

            context.report(.finalizing, currentPath: "/")
            _ = try refreshFolderMetadata(folderID: 1, database: database)
            try execute("COMMIT;", database: database)

            let previousFolderCount: Int?
            let previousComicCount: Int?
            let reusedComicCount: Int?

            switch mode {
            case .initial:
                previousFolderCount = nil
                previousComicCount = nil
                reusedComicCount = nil
            case .rebuildPreservingComicRelationships:
                previousFolderCount = snapshot.existingFolderCount
                previousComicCount = snapshot.existingComicCount
                reusedComicCount = context.consumedReusableComicIDs.count
            }

            return LibraryScanSummary(
                folderCount: context.summary.folderCount,
                comicCount: context.summary.comicCount,
                previousFolderCount: previousFolderCount,
                previousComicCount: previousComicCount,
                reusedComicCount: reusedComicCount
            )
        } catch {
            _ = try? execute("ROLLBACK;", database: database)
            throw error
        }
    }

    private func performSubtreeRefresh(
        sourceRootURL: URL,
        databaseURL: URL,
        folder: LibraryFolder,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        try cancellationCheck?()
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryScannerError.databaseMissing
        }

        let summary = SQLiteDatabaseInspector().inspectDatabase(at: databaseURL)
        guard summary.hasCompatibleSchemaVersion else {
            let versionText = summary.version ?? "Unknown"
            throw LibraryScannerError.incompatibleDatabaseVersion(
                "This library uses DB \(versionText), which is not supported for scanning on this iOS build."
            )
        }

        let targetDirectoryURL = resolveDirectoryURL(for: folder, sourceRootURL: sourceRootURL)
        guard fileManager.fileExists(atPath: targetDirectoryURL.path) else {
            throw LibraryScannerError.scanFailed("The folder `\(folder.displayName)` no longer exists on disk.")
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryScannerError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        try execute("PRAGMA foreign_keys = ON;", database: database)
        try execute("BEGIN TRANSACTION;", database: database)

        do {
            try cancellationCheck?()
            progressHandler?(
                LibraryScanProgress(
                    phase: .preparing,
                    currentPath: folder.path,
                    processedFolderCount: 0,
                    processedComicCount: 0
                )
            )

            let coversRootURL = databaseURL
                .deletingLastPathComponent()
                .appendingPathComponent("covers", isDirectory: true)

            let snapshot = try makeSubtreeRescanSnapshot(
                rootFolderID: folder.id,
                database: database
            )
            try clearIndexedSubtree(
                rootFolderID: folder.id,
                database: database
            )

            let context = ScanContext(
                sourceRootURL: sourceRootURL,
                coversRootURL: coversRootURL,
                snapshot: snapshot,
                progressHandler: progressHandler
            )

            try scanDirectory(
                at: targetDirectoryURL,
                parentFolderID: folder.id,
                database: database,
                context: context,
                cancellationCheck: cancellationCheck
            )

            try cancellationCheck?()
            try restoreMemberships(
                snapshot: snapshot,
                survivingComicIDs: context.insertedComicIDs,
                database: database
            )

            context.report(.finalizing, currentPath: folder.path)
            _ = try refreshFolderMetadata(folderID: 1, database: database)
            try execute("COMMIT;", database: database)
            return LibraryScanSummary(
                folderCount: context.summary.folderCount,
                comicCount: context.summary.comicCount,
                previousFolderCount: snapshot.existingFolderCount,
                previousComicCount: snapshot.existingComicCount,
                reusedComicCount: context.consumedReusableComicIDs.count
            )
        } catch {
            _ = try? execute("ROLLBACK;", database: database)
            throw error
        }
    }

    private func scanDirectory(
        at directoryURL: URL,
        parentFolderID: Int64,
        database: OpaquePointer,
        context: ScanContext,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        try cancellationCheck?()
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .nameKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .isHiddenKey
            ],
            options: [.skipsHiddenFiles]
        )

        let sortedContents = contents.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        let directories = sortedContents.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && url.lastPathComponent != ".yacreaderlibrary"
        }

        let files = sortedContents.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && isSupportedComicFile(url)
        }

        for subdirectoryURL in directories {
            try cancellationCheck?()
            let relativePath = makeRelativePath(for: subdirectoryURL, sourceRootURL: context.sourceRootURL)
            let folderID = try insertFolder(
                name: subdirectoryURL.lastPathComponent,
                relativePath: relativePath,
                parentFolderID: parentFolderID,
                database: database
            )
            context.summary = LibraryScanSummary(
                folderCount: context.summary.folderCount + 1,
                comicCount: context.summary.comicCount
            )
            context.report(.scanningFolders, currentPath: relativePath)

            try scanDirectory(
                at: subdirectoryURL,
                parentFolderID: folderID,
                database: database,
                context: context,
                cancellationCheck: cancellationCheck
            )
        }

        for fileURL in files {
            try cancellationCheck?()
            let relativePath = makeRelativePath(for: fileURL, sourceRootURL: context.sourceRootURL)
            try insertComic(
                fileURL: fileURL,
                relativePath: relativePath,
                parentFolderID: parentFolderID,
                database: database,
                context: context
            )
            context.summary = LibraryScanSummary(
                folderCount: context.summary.folderCount,
                comicCount: context.summary.comicCount + 1
            )
            context.reportComicProgressIfNeeded(currentPath: relativePath)
        }
    }

    private func insertFolder(
        name: String,
        relativePath: String,
        parentFolderID: Int64,
        database: OpaquePointer
    ) throws -> Int64 {
        let sql = """
        INSERT INTO folder (parentId, name, path, added, type)
        VALUES (?, ?, ?, strftime('%s','now'), 0)
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)
        sqlite3_bind_text(statement, 2, name, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, relativePath, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        return sqlite3_last_insert_rowid(database)
    }

    private func insertComic(
        fileURL: URL,
        relativePath: String,
        parentFolderID: Int64,
        database: OpaquePointer,
        context: ScanContext
    ) throws {
        let hash = try pseudoHash(for: fileURL)
        let reusableComicRecord = reusableComicRecord(
            for: relativePath,
            hash: hash,
            context: context
        )
        let comicInfoResolution = try ensureComicInfo(
            hash: hash,
            database: database
        )
        let comicInfoID = comicInfoResolution.id
        // Lightweight import: only extract page count (no cover image, no ComicInfo.xml).
        // Cover and metadata will be extracted lazily when the comic is first opened.
        if let pageCount = metadataExtractor.extractPageCountOnly(for: fileURL), pageCount > 0 {
            try applyPageCount(
                pageCount,
                comicInfoID: comicInfoID,
                database: database
            )
        }

        let sql: String
        if reusableComicRecord != nil {
            sql = """
            INSERT INTO comic (id, parentId, comicInfoId, fileName, path)
            VALUES (?, ?, ?, ?, ?)
            """
        } else {
            sql = """
            INSERT INTO comic (parentId, comicInfoId, fileName, path)
            VALUES (?, ?, ?, ?)
            """
        }

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        if let reusableComicRecord {
            sqlite3_bind_int64(statement, 1, reusableComicRecord.comicID)
            sqlite3_bind_int64(statement, 2, parentFolderID)
            sqlite3_bind_int64(statement, 3, comicInfoID)
            sqlite3_bind_text(statement, 4, fileURL.lastPathComponent, -1, transientDestructor)
            sqlite3_bind_text(statement, 5, relativePath, -1, transientDestructor)
        } else {
            sqlite3_bind_int64(statement, 1, parentFolderID)
            sqlite3_bind_int64(statement, 2, comicInfoID)
            sqlite3_bind_text(statement, 3, fileURL.lastPathComponent, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, relativePath, -1, transientDestructor)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        let insertedComicID = reusableComicRecord?.comicID ?? sqlite3_last_insert_rowid(database)
        context.insertedComicIDs.insert(insertedComicID)
    }

    private func appendImportedComic(
        fileURL: URL,
        relativePath: String,
        parentFolderID: Int64,
        database: OpaquePointer
    ) throws {
        let hash = try pseudoHash(for: fileURL)
        let comicInfoID = try ensureComicInfo(
            hash: hash,
            database: database
        ).id

        if let pageCount = metadataExtractor.extractPageCountOnly(for: fileURL), pageCount > 0 {
            try applyPageCount(
                pageCount,
                comicInfoID: comicInfoID,
                database: database
            )
        }

        let statement = try prepareStatement(
            """
            INSERT INTO comic (parentId, comicInfoId, fileName, path)
            VALUES (?, ?, ?, ?)
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)
        sqlite3_bind_int64(statement, 2, comicInfoID)
        sqlite3_bind_text(statement, 3, fileURL.lastPathComponent, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, relativePath, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func ensureComicInfo(hash: String, database: OpaquePointer) throws -> ComicInfoResolution {
        if let existingID = try loadComicInfoID(hash: hash, database: database) {
            return ComicInfoResolution(id: existingID, isNew: false)
        }

        let insertSQL = """
        INSERT INTO comic_info (hash, added, type)
        VALUES (?, strftime('%s','now'), 0)
        """

        let statement = try prepareStatement(insertSQL, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, hash, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        return ComicInfoResolution(
            id: sqlite3_last_insert_rowid(database),
            isNew: true
        )
    }

    private func loadComicInfoID(hash: String, database: OpaquePointer) throws -> Int64? {
        let statement = try prepareStatement(
            "SELECT id FROM comic_info WHERE hash = ? LIMIT 1",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, hash, -1, transientDestructor)

        if sqlite3_step(statement) == SQLITE_ROW {
            return sqlite3_column_int64(statement, 0)
        }

        return nil
    }

    private func loadCoverPage(comicInfoID: Int64, database: OpaquePointer) throws -> Int {
        let statement = try prepareStatement(
            "SELECT coverPage FROM comic_info WHERE id = ? LIMIT 1",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, comicInfoID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 1
        }

        let coverPage = Int(sqlite3_column_int64(statement, 0))
        return max(1, coverPage)
    }

    private func applyExtractedMetadata(
        _ metadata: ExtractedComicMetadata,
        comicInfoID: Int64,
        hash: String,
        coversRootURL: URL,
        shouldImportComicInfoXML: Bool,
        database: OpaquePointer
    ) throws {
        if let coverImage = metadata.coverImage {
            let coverURL = coversRootURL.appendingPathComponent("\(hash).jpg")
            try metadataExtractor.saveCover(coverImage, to: coverURL)
        }

        let sql = """
        UPDATE comic_info
        SET numPages = ?,
            coverSizeRatio = ?,
            originalCoverSize = ?
        WHERE id = ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(metadata.pageCount))

        if let coverSizeRatio = metadata.coverSizeRatio {
            sqlite3_bind_double(statement, 2, coverSizeRatio)
        } else {
            sqlite3_bind_null(statement, 2)
        }

        bindNullableText(metadata.originalCoverSizeString, at: 3, statement: statement)
        sqlite3_bind_int64(statement, 4, comicInfoID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        if shouldImportComicInfoXML, let importedComicInfo = metadata.importedComicInfo {
            try applyImportedComicInfo(
                importedComicInfo,
                comicInfoID: comicInfoID,
                database: database
            )
        }
    }

    private func applyPageCount(
        _ pageCount: Int,
        comicInfoID: Int64,
        database: OpaquePointer
    ) throws {
        let sql = """
        UPDATE comic_info
        SET numPages = ?
        WHERE id = ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(pageCount))
        sqlite3_bind_int64(statement, 2, comicInfoID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func applyImportedComicInfo(
        _ metadata: ImportedComicInfoMetadata,
        comicInfoID: Int64,
        database: OpaquePointer
    ) throws {
        let sql = """
        UPDATE comic_info
        SET title = ?,
            number = ?,
            count = ?,
            volume = ?,
            storyArc = ?,
            genere = ?,
            writer = ?,
            penciller = ?,
            inker = ?,
            colorist = ?,
            letterer = ?,
            coverArtist = ?,
            date = ?,
            publisher = ?,
            format = ?,
            color = ?,
            ageRating = ?,
            synopsis = ?,
            characters = ?,
            notes = ?,
            comicVineID = ?,
            type = CASE
                WHEN ? IS NULL THEN type
                ELSE ?
            END,
            manga = CASE
                WHEN ? IS NULL THEN manga
                ELSE ?
            END,
            editor = ?,
            imprint = ?,
            teams = ?,
            locations = ?,
            series = ?,
            alternateSeries = ?,
            alternateNumber = ?,
            alternateCount = ?,
            languageISO = ?,
            seriesGroup = ?,
            mainCharacterOrTeam = ?,
            review = ?,
            tags = ?,
            lastTimeMetadataSet = strftime('%s','now')
        WHERE id = ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        bindNullableText(metadata.title, at: 1, statement: statement)
        bindNullableText(metadata.issueNumber, at: 2, statement: statement)
        bindNullableInt64(metadata.count.map(Int64.init), at: 3, statement: statement)
        bindNullableText(metadata.volume, at: 4, statement: statement)
        bindNullableText(metadata.storyArc, at: 5, statement: statement)
        bindNullableText(metadata.genre, at: 6, statement: statement)
        bindNullableText(metadata.writer, at: 7, statement: statement)
        bindNullableText(metadata.penciller, at: 8, statement: statement)
        bindNullableText(metadata.inker, at: 9, statement: statement)
        bindNullableText(metadata.colorist, at: 10, statement: statement)
        bindNullableText(metadata.letterer, at: 11, statement: statement)
        bindNullableText(metadata.coverArtist, at: 12, statement: statement)
        bindNullableText(metadata.publicationDate, at: 13, statement: statement)
        bindNullableText(metadata.publisher, at: 14, statement: statement)
        bindNullableText(metadata.format, at: 15, statement: statement)
        bindNullableBool(metadata.isColor, at: 16, statement: statement)
        bindNullableText(metadata.ageRating, at: 17, statement: statement)
        bindNullableText(metadata.synopsis, at: 18, statement: statement)
        bindNullableText(metadata.characters, at: 19, statement: statement)
        bindNullableText(metadata.notes, at: 20, statement: statement)
        bindNullableText(metadata.comicVineID, at: 21, statement: statement)

        let importedType = metadata.type.map { Int64($0.rawValue) }
        bindNullableInt64(importedType, at: 22, statement: statement)
        bindNullableInt64(importedType, at: 23, statement: statement)

        let mangaFlag = metadata.type.map { $0 == .manga ? Int64(1) : Int64(0) }
        bindNullableInt64(mangaFlag, at: 24, statement: statement)
        bindNullableInt64(mangaFlag, at: 25, statement: statement)

        bindNullableText(metadata.editor, at: 26, statement: statement)
        bindNullableText(metadata.imprint, at: 27, statement: statement)
        bindNullableText(metadata.teams, at: 28, statement: statement)
        bindNullableText(metadata.locations, at: 29, statement: statement)
        bindNullableText(metadata.series, at: 30, statement: statement)
        bindNullableText(metadata.alternateSeries, at: 31, statement: statement)
        bindNullableText(metadata.alternateNumber, at: 32, statement: statement)
        bindNullableInt64(metadata.alternateCount.map(Int64.init), at: 33, statement: statement)
        bindNullableText(metadata.languageISO, at: 34, statement: statement)
        bindNullableText(metadata.seriesGroup, at: 35, statement: statement)
        bindNullableText(metadata.mainCharacterOrTeam, at: 36, statement: statement)
        bindNullableText(metadata.review, at: 37, statement: statement)
        bindNullableText(metadata.tags, at: 38, statement: statement)
        sqlite3_bind_int64(statement, 39, comicInfoID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func refreshFolderMetadata(folderID: Int64, database: OpaquePointer) throws -> String? {
        let subfolders = try loadChildFolders(parentFolderID: folderID, database: database)

        var firstChildHashFromSubfolder: String?
        for childFolder in subfolders {
            let childHash = try refreshFolderMetadata(folderID: childFolder.id, database: database)
            if firstChildHashFromSubfolder == nil, let childHash, !childHash.isEmpty {
                firstChildHashFromSubfolder = childHash
            }
        }

        let comicCount = try loadComicCount(parentFolderID: folderID, database: database)
        let firstComicHash = try loadFirstComicHash(parentFolderID: folderID, database: database)
        let firstChildHash = firstComicHash ?? firstChildHashFromSubfolder
        let childCount = subfolders.count + comicCount

        let statement = try prepareStatement(
            "UPDATE folder SET numChildren = ?, firstChildHash = ? WHERE id = ?",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(childCount))
        bindNullableText(firstChildHash, at: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, folderID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        return firstChildHash
    }

    private func loadChildFolders(parentFolderID: Int64, database: OpaquePointer) throws -> [(id: Int64, name: String)] {
        let statement = try prepareStatement(
            "SELECT id, name FROM folder WHERE parentId = ? AND id <> 1 ORDER BY name COLLATE NOCASE",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        var results: [(id: Int64, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let name = stringValue(at: 1, statement: statement) ?? ""
            results.append((id: id, name: name))
        }

        return results
    }

    private func loadComicCount(parentFolderID: Int64, database: OpaquePointer) throws -> Int {
        let statement = try prepareStatement(
            "SELECT COUNT(*) FROM comic WHERE parentId = ?",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func loadFirstComicHash(parentFolderID: Int64, database: OpaquePointer) throws -> String? {
        let sql = """
        SELECT ci.hash
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE c.parentId = ?
        ORDER BY c.fileName COLLATE NOCASE
        LIMIT 1
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return stringValue(at: 0, statement: statement)
    }

    private func pseudoHash(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let data = try handle.read(upToCount: 524_288) ?? Data()
        let digest = Insecure.SHA1.hash(data: data)
        let hashPrefix = digest.map { String(format: "%02x", $0) }.joined()
        let fileSize = (try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return hashPrefix + String(fileSize)
    }

    private func makeRelativePath(for url: URL, sourceRootURL: URL) -> String {
        let rootPath = sourceRootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path

        if targetPath == rootPath {
            return "/"
        }

        var relativePath = String(targetPath.dropFirst(rootPath.count))
        if !relativePath.hasPrefix("/") {
            relativePath = "/" + relativePath
        }

        return relativePath
    }

    private func isSupportedComicFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func reusableComicRecord(
        for relativePath: String,
        hash: String,
        context: ScanContext
    ) -> ExistingComicRecord? {
        if let record = context.reusableComicsByPath[relativePath],
           !context.consumedReusableComicIDs.contains(record.comicID) {
            context.consumedReusableComicIDs.insert(record.comicID)
            return record
        }

        if let candidates = context.reusableComicsByHash[hash],
           let record = candidates.first(where: { !context.consumedReusableComicIDs.contains($0.comicID) }) {
            context.consumedReusableComicIDs.insert(record.comicID)
            return record
        }

        return nil
    }

    private func makeRescanSnapshot(database: OpaquePointer) throws -> RescanSnapshot {
        let existingComics = try loadExistingComics(database: database)
        let comicsByPath = existingComics.reduce(into: [String: ExistingComicRecord]()) { partialResult, record in
            guard let relativePath = record.relativePath else {
                return
            }

            partialResult[relativePath] = record
        }
        let comicsByHash = Dictionary(grouping: existingComics, by: \.hash)

        return RescanSnapshot(
            existingFolderCount: try loadIndexedFolderCount(database: database),
            existingComicCount: existingComics.count,
            comicsByPath: comicsByPath,
            comicsByHash: comicsByHash,
            labelMemberships: try loadLabelMembershipSnapshots(database: database),
            readingListMemberships: try loadReadingListMembershipSnapshots(database: database),
            defaultReadingListMemberships: try loadDefaultReadingListMembershipSnapshots(database: database)
        )
    }

    private func makeSubtreeRescanSnapshot(
        rootFolderID: Int64,
        database: OpaquePointer
    ) throws -> RescanSnapshot {
        let subtreeFolderIDs = try loadSubtreeFolderIDs(rootFolderID: rootFolderID, database: database)
        let existingComics = try loadExistingComics(inFolderIDs: subtreeFolderIDs, database: database)
        let comicsByPath = existingComics.reduce(into: [String: ExistingComicRecord]()) { partialResult, record in
            guard let relativePath = record.relativePath else {
                return
            }

            partialResult[relativePath] = record
        }

        let comicsByHash = Dictionary(grouping: existingComics, by: \.hash)
        let comicIDs = existingComics.map(\.comicID)

        return RescanSnapshot(
            existingFolderCount: max(0, subtreeFolderIDs.count - 1),
            existingComicCount: existingComics.count,
            comicsByPath: comicsByPath,
            comicsByHash: comicsByHash,
            labelMemberships: try loadLabelMembershipSnapshots(comicIDs: comicIDs, database: database),
            readingListMemberships: try loadReadingListMembershipSnapshots(comicIDs: comicIDs, database: database),
            defaultReadingListMemberships: try loadDefaultReadingListMembershipSnapshots(comicIDs: comicIDs, database: database)
        )
    }

    private func loadIndexedFolderCount(database: OpaquePointer) throws -> Int {
        let statement = try prepareStatement(
            "SELECT COUNT(*) FROM folder WHERE id <> 1",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func loadIndexedComicCount(database: OpaquePointer) throws -> Int {
        let statement = try prepareStatement(
            "SELECT COUNT(*) FROM comic",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func clearIndexedLibraryStructure(database: OpaquePointer) throws {
        try execute("DELETE FROM comic;", database: database)
        try execute("DELETE FROM folder WHERE id <> 1;", database: database)
        try execute(
            "UPDATE folder SET numChildren = 0, firstChildHash = NULL, updated = strftime('%s','now') WHERE id = 1;",
            database: database
        )
    }

    private func clearIndexedSubtree(
        rootFolderID: Int64,
        database: OpaquePointer
    ) throws {
        let subtreeFolderIDs = try loadSubtreeFolderIDs(rootFolderID: rootFolderID, database: database)
        let descendantFolderIDs = subtreeFolderIDs.filter { $0 != rootFolderID }

        try executeDelete(
            from: "comic",
            whereColumn: "parentId",
            matching: subtreeFolderIDs,
            database: database
        )

        try executeDelete(
            from: "folder",
            whereColumn: "id",
            matching: descendantFolderIDs,
            database: database
        )

        let statement = try prepareStatement(
            """
            UPDATE folder
            SET numChildren = 0,
                firstChildHash = NULL,
                updated = strftime('%s','now')
            WHERE id = ?
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, rootFolderID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func restoreMemberships(
        snapshot: RescanSnapshot,
        survivingComicIDs: Set<Int64>,
        database: OpaquePointer
    ) throws {
        try restoreLabelMemberships(
            snapshot.labelMemberships.filter { survivingComicIDs.contains($0.comicID) },
            database: database
        )
        try restoreReadingListMemberships(
            snapshot.readingListMemberships.filter { survivingComicIDs.contains($0.comicID) },
            database: database
        )
        try restoreDefaultReadingListMemberships(
            snapshot.defaultReadingListMemberships.filter { survivingComicIDs.contains($0.comicID) },
            database: database
        )
    }

    private func loadExistingComics(database: OpaquePointer) throws -> [ExistingComicRecord] {
        let sql = """
        SELECT c.id, c.comicInfoId, ci.hash, c.path
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        var records: [ExistingComicRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(
                ExistingComicRecord(
                    comicID: sqlite3_column_int64(statement, 0),
                    comicInfoID: sqlite3_column_int64(statement, 1),
                    hash: stringValue(at: 2, statement: statement) ?? "",
                    relativePath: stringValue(at: 3, statement: statement)
                )
            )
        }

        return records
    }

    private func loadExistingComicPaths(database: OpaquePointer) throws -> Set<String> {
        let statement = try prepareStatement(
            "SELECT path FROM comic WHERE path IS NOT NULL",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        var paths = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let path = stringValue(at: 0, statement: statement), !path.isEmpty {
                paths.insert(path)
            }
        }

        return paths
    }

    private func pruneMissingComicRows(
        sourceRootURL: URL,
        database: OpaquePointer
    ) throws {
        for relativePath in try loadExistingComicPaths(database: database) {
            let fileURL = fileURL(forRelativePath: relativePath, sourceRootURL: sourceRootURL)
            guard !fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            try deleteComicRows(forRelativePath: relativePath, database: database)
        }
    }

    private func collapseDuplicateComicRows(
        forRelativePaths relativePaths: [String],
        database: OpaquePointer
    ) throws {
        for relativePath in Set(relativePaths) {
            let comicIDs = try loadComicIDs(forRelativePath: relativePath, database: database)
            guard comicIDs.count > 1 else {
                continue
            }

            for duplicateID in comicIDs.dropFirst() {
                try deleteComic(id: duplicateID, database: database)
            }
        }
    }

    private func loadComicIDs(
        forRelativePath relativePath: String,
        database: OpaquePointer
    ) throws -> [Int64] {
        let statement = try prepareStatement(
            """
            SELECT id
            FROM comic
            WHERE path = ?
            ORDER BY id ASC
            """,
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, relativePath, -1, transientDestructor)

        var comicIDs: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            comicIDs.append(sqlite3_column_int64(statement, 0))
        }

        return comicIDs
    }

    private func deleteComicRows(
        forRelativePath relativePath: String,
        database: OpaquePointer
    ) throws {
        let statement = try prepareStatement(
            "DELETE FROM comic WHERE path = ?",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, relativePath, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func deleteComic(id: Int64, database: OpaquePointer) throws {
        let statement = try prepareStatement(
            "DELETE FROM comic WHERE id = ?",
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func fileURL(
        forRelativePath relativePath: String,
        sourceRootURL: URL
    ) -> URL {
        let trimmedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else {
            return sourceRootURL
        }

        let pathComponents = trimmedPath
            .split(separator: "/")
            .map(String.init)
        return pathComponents.reduce(sourceRootURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func loadExistingComics(
        inFolderIDs folderIDs: [Int64],
        database: OpaquePointer
    ) throws -> [ExistingComicRecord] {
        guard !folderIDs.isEmpty else {
            return []
        }

        let placeholders = sqlPlaceholders(count: folderIDs.count)
        let sql = """
        SELECT c.id, c.comicInfoId, ci.hash, c.path
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE c.parentId IN (\(placeholders))
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        bindInt64Values(folderIDs, startingAt: 1, statement: statement)

        var records: [ExistingComicRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(
                ExistingComicRecord(
                    comicID: sqlite3_column_int64(statement, 0),
                    comicInfoID: sqlite3_column_int64(statement, 1),
                    hash: stringValue(at: 2, statement: statement) ?? "",
                    relativePath: stringValue(at: 3, statement: statement)
                )
            )
        }

        return records
    }

    private func loadLabelMembershipSnapshots(
        comicIDs: [Int64]? = nil,
        database: OpaquePointer
    ) throws -> [LabelMembershipSnapshot] {
        let statement = try prepareStatement(
            membershipSnapshotSQL(
                tableName: "comic_label",
                relationColumnName: "label_id",
                comicIDs: comicIDs
            ),
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        if let comicIDs {
            bindInt64Values(comicIDs, startingAt: 1, statement: statement)
        }

        var results: [LabelMembershipSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(
                LabelMembershipSnapshot(
                    labelID: sqlite3_column_int64(statement, 0),
                    comicID: sqlite3_column_int64(statement, 1),
                    ordering: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 2)
                )
            )
        }

        return results
    }

    private func loadReadingListMembershipSnapshots(
        comicIDs: [Int64]? = nil,
        database: OpaquePointer
    ) throws -> [ReadingListMembershipSnapshot] {
        let statement = try prepareStatement(
            membershipSnapshotSQL(
                tableName: "comic_reading_list",
                relationColumnName: "reading_list_id",
                comicIDs: comicIDs
            ),
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        if let comicIDs {
            bindInt64Values(comicIDs, startingAt: 1, statement: statement)
        }

        var results: [ReadingListMembershipSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(
                ReadingListMembershipSnapshot(
                    readingListID: sqlite3_column_int64(statement, 0),
                    comicID: sqlite3_column_int64(statement, 1),
                    ordering: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 2)
                )
            )
        }

        return results
    }

    private func loadDefaultReadingListMembershipSnapshots(
        comicIDs: [Int64]? = nil,
        database: OpaquePointer
    ) throws -> [DefaultReadingListMembershipSnapshot] {
        let statement = try prepareStatement(
            membershipSnapshotSQL(
                tableName: "comic_default_reading_list",
                relationColumnName: "default_reading_list_id",
                comicIDs: comicIDs
            ),
            database: database
        )
        defer {
            sqlite3_finalize(statement)
        }

        if let comicIDs {
            bindInt64Values(comicIDs, startingAt: 1, statement: statement)
        }

        var results: [DefaultReadingListMembershipSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(
                DefaultReadingListMembershipSnapshot(
                    defaultReadingListID: sqlite3_column_int64(statement, 0),
                    comicID: sqlite3_column_int64(statement, 1),
                    ordering: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 2)
                )
            )
        }

        return results
    }

    private func loadSubtreeFolderIDs(
        rootFolderID: Int64,
        database: OpaquePointer
    ) throws -> [Int64] {
        let sql = """
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id FROM folder WHERE id = ?
            UNION ALL
            SELECT f.id
            FROM folder f
            INNER JOIN folder_tree tree ON f.parentId = tree.id
            WHERE f.id <> tree.id
        )
        SELECT id FROM folder_tree
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, rootFolderID)

        var ids: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(statement, 0))
        }

        return ids
    }

    private func restoreLabelMemberships(
        _ memberships: [LabelMembershipSnapshot],
        database: OpaquePointer
    ) throws {
        let sql = """
        INSERT OR IGNORE INTO comic_label (label_id, comic_id, ordering)
        VALUES (?, ?, ?)
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        for membership in memberships {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, membership.labelID)
            sqlite3_bind_int64(statement, 2, membership.comicID)

            if let ordering = membership.ordering {
                sqlite3_bind_int64(statement, 3, ordering)
            } else {
                sqlite3_bind_null(statement, 3)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
            }
        }
    }

    private func restoreReadingListMemberships(
        _ memberships: [ReadingListMembershipSnapshot],
        database: OpaquePointer
    ) throws {
        let sql = """
        INSERT OR IGNORE INTO comic_reading_list (reading_list_id, comic_id, ordering)
        VALUES (?, ?, ?)
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        for membership in memberships {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, membership.readingListID)
            sqlite3_bind_int64(statement, 2, membership.comicID)

            if let ordering = membership.ordering {
                sqlite3_bind_int64(statement, 3, ordering)
            } else {
                sqlite3_bind_null(statement, 3)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
            }
        }
    }

    private func restoreDefaultReadingListMemberships(
        _ memberships: [DefaultReadingListMembershipSnapshot],
        database: OpaquePointer
    ) throws {
        let sql = """
        INSERT OR IGNORE INTO comic_default_reading_list (default_reading_list_id, comic_id, ordering)
        VALUES (?, ?, ?)
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        for membership in memberships {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, membership.defaultReadingListID)
            sqlite3_bind_int64(statement, 2, membership.comicID)

            if let ordering = membership.ordering {
                sqlite3_bind_int64(statement, 3, ordering)
            } else {
                sqlite3_bind_null(statement, 3)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
            }
        }
    }

    private func prepareStatement(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }

        return statement
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func executeDelete(
        from tableName: String,
        whereColumn: String,
        matching values: [Int64],
        database: OpaquePointer
    ) throws {
        guard !values.isEmpty else {
            return
        }

        let sql = """
        DELETE FROM \(tableName)
        WHERE \(whereColumn) IN (\(sqlPlaceholders(count: values.count)))
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        bindInt64Values(values, startingAt: 1, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryScannerError.scanFailed(lastDatabaseError(database: database))
        }
    }

    private func membershipSnapshotSQL(
        tableName: String,
        relationColumnName: String,
        comicIDs: [Int64]?
    ) -> String {
        if let comicIDs, !comicIDs.isEmpty {
            return """
            SELECT \(relationColumnName), comic_id, ordering
            FROM \(tableName)
            WHERE comic_id IN (\(sqlPlaceholders(count: comicIDs.count)))
            """
        }

        return """
        SELECT \(relationColumnName), comic_id, ordering
        FROM \(tableName)
        """
    }

    private func sqlPlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private func bindInt64Values(
        _ values: [Int64],
        startingAt startIndex: Int32,
        statement: OpaquePointer
    ) {
        for (offset, value) in values.enumerated() {
            sqlite3_bind_int64(statement, startIndex + Int32(offset), value)
        }
    }

    private func resolveDirectoryURL(
        for folder: LibraryFolder,
        sourceRootURL: URL
    ) -> URL {
        guard !folder.isRoot else {
            return sourceRootURL
        }

        let relativePath = folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            return sourceRootURL
        }

        return sourceRootURL.appendingPathComponent(relativePath, isDirectory: true)
    }

    private func bindNullableText(_ text: String?, at index: Int32, statement: OpaquePointer) {
        if let text {
            sqlite3_bind_text(statement, index, text, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindNullableInt64(_ value: Int64?, at index: Int32, statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindNullableBool(_ value: Bool?, at index: Int32, statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int(statement, index, value ? 1 : 0)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func stringValue(at index: Int32, statement: OpaquePointer) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: value)
    }

    private func lastDatabaseError(database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }

    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    #endif
}
