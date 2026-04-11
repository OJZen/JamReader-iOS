import CryptoKit
import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

final class LibraryIndexingService {
    private struct ScannedFolder {
        let relativePath: String
        let parentRelativePath: String?
        let name: String
    }

    private struct ScannedComic {
        let relativePath: String
        let parentRelativePath: String
        let fileName: String
        let hash: String
        let metadata: ExtractedComicMetadata?
    }

    private struct ExistingComicRecord {
        let id: Int64
        let relativePath: String
        let hash: String
    }

    private let database: AppLibraryDatabase
    private let assetStore: LibraryAssetStore
    private let fileManager: FileManager
    private let metadataExtractor: LibraryComicMetadataExtractor
    private let directoryImageSequenceInspector: DirectoryImageSequenceInspector
    private let supportedExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf", "epub", "mobi"
    ]

    init(
        database: AppLibraryDatabase,
        assetStore: LibraryAssetStore,
        fileManager: FileManager = .default,
        metadataExtractor: LibraryComicMetadataExtractor = LibraryComicMetadataExtractor(),
        directoryImageSequenceInspector: DirectoryImageSequenceInspector = DirectoryImageSequenceInspector()
    ) {
        self.database = database
        self.assetStore = assetStore
        self.fileManager = fileManager
        self.metadataExtractor = metadataExtractor
        self.directoryImageSequenceInspector = directoryImageSequenceInspector
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)? = nil,
        progressHandler: ((LibraryScanProgress) -> Void)? = nil
    ) throws -> LibraryScanSummary {
        try performFullScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
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
        try performFullScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
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
        _ = folder
        return try performFullScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
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
        _ = fileURLs
        return try performFullScan(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    private func performFullScan(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        guard let libraryID = database.libraryID(from: databaseURL) else {
            throw NativeLibraryStorageError.invalidLibraryContext
        }

        try database.ensureInitialized()
        try assetStore.ensureLibraryDirectories(for: libraryID)
        try cancellationCheck?()

        progressHandler?(
            LibraryScanProgress(
                phase: .preparing,
                currentPath: "/",
                processedFolderCount: 0,
                processedComicCount: 0
            )
        )

        let discovery = try discoverLibraryContents(
            at: sourceRootURL.standardizedFileURL,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )

        progressHandler?(
            LibraryScanProgress(
                phase: .finalizing,
                currentPath: "/",
                processedFolderCount: discovery.folders.count - 1,
                processedComicCount: discovery.comics.count
            )
        )

        return try syncDiscoveredContents(
            discovery,
            libraryID: libraryID,
            cancellationCheck: cancellationCheck
        )
    }

    private func discoverLibraryContents(
        at sourceRootURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> (folders: [ScannedFolder], comics: [ScannedComic]) {
        guard let enumerator = fileManager.enumerator(
            at: sourceRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            throw NativeLibraryStorageError.executionFailed("Unable to enumerate the library folder.")
        }

        var folders: [ScannedFolder] = [
            ScannedFolder(relativePath: "", parentRelativePath: nil, name: "root")
        ]
        var comics: [ScannedComic] = []
        var processedFolderCount = 0
        var processedComicCount = 0

        while let itemURL = enumerator.nextObject() as? URL {
            try cancellationCheck?()

            let standardizedURL = itemURL.standardizedFileURL
            let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            let isDirectory = values.isDirectory == true
            let isRegularFile = values.isRegularFile == true
            let name = standardizedURL.lastPathComponent

            if shouldIgnoreDirectoryComponent(named: name) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                if let inspection = try directoryImageSequenceInspector.inspectComicDirectory(at: standardizedURL) {
                    let relativePath = makeRelativePath(for: standardizedURL, sourceRootURL: sourceRootURL)
                    let metadata: ExtractedComicMetadata?
                    do {
                        metadata = try metadataExtractor.extractMetadata(for: standardizedURL)
                    } catch {
                        metadata = nil
                    }

                    comics.append(
                        ScannedComic(
                            relativePath: relativePath,
                            parentRelativePath: relativeDirectoryPath(for: relativePath) ?? "",
                            fileName: standardizedURL.lastPathComponent,
                            hash: try directoryImageSequenceInspector.fingerprint(for: inspection),
                            metadata: metadata
                        )
                    )

                    processedComicCount += 1
                    if processedComicCount == 1 || processedComicCount.isMultiple(of: 5) {
                        progressHandler?(
                            LibraryScanProgress(
                                phase: .scanningComics,
                                currentPath: displayPath(fromRelativePath: relativePath),
                                processedFolderCount: processedFolderCount,
                                processedComicCount: processedComicCount
                            )
                        )
                    }

                    enumerator.skipDescendants()
                    continue
                }

                let relativePath = makeRelativePath(for: standardizedURL, sourceRootURL: sourceRootURL)
                let parentRelativePath = relativeDirectoryPath(for: relativePath)
                folders.append(
                    ScannedFolder(
                        relativePath: relativePath,
                        parentRelativePath: parentRelativePath,
                        name: name
                    )
                )
                processedFolderCount += 1
                progressHandler?(
                    LibraryScanProgress(
                        phase: .scanningFolders,
                        currentPath: displayPath(fromRelativePath: relativePath),
                        processedFolderCount: processedFolderCount,
                        processedComicCount: processedComicCount
                    )
                )
                continue
            }

            guard isRegularFile, supportedExtensions.contains(standardizedURL.pathExtension.lowercased()) else {
                continue
            }

            let relativePath = makeRelativePath(for: standardizedURL, sourceRootURL: sourceRootURL)
            let metadata: ExtractedComicMetadata?
            do {
                metadata = try metadataExtractor.extractMetadata(for: standardizedURL)
            } catch {
                metadata = nil
            }

            comics.append(
                ScannedComic(
                    relativePath: relativePath,
                    parentRelativePath: relativeDirectoryPath(for: relativePath) ?? "",
                    fileName: standardizedURL.lastPathComponent,
                    hash: try fileFingerprint(for: standardizedURL),
                    metadata: metadata
                )
            )

            processedComicCount += 1
            if processedComicCount == 1 || processedComicCount.isMultiple(of: 5) {
                progressHandler?(
                    LibraryScanProgress(
                        phase: .scanningComics,
                        currentPath: displayPath(fromRelativePath: relativePath),
                        processedFolderCount: processedFolderCount,
                        processedComicCount: processedComicCount
                    )
                )
            }
        }

        let sortedFolders = folders.sorted { lhs, rhs in
            let lhsDepth = lhs.relativePath.split(separator: "/").count
            let rhsDepth = rhs.relativePath.split(separator: "/").count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }

            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        let sortedComics = comics.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }

        return (sortedFolders, sortedComics)
    }

    private func syncDiscoveredContents(
        _ discovery: (folders: [ScannedFolder], comics: [ScannedComic]),
        libraryID: UUID,
        cancellationCheck: (() throws -> Void)?
    ) throws -> LibraryScanSummary {
        let previousCounts = try currentCounts(for: libraryID)
        let currentFolderPaths = Set(discovery.folders.map(\.relativePath))
        var currentHashes = Set<String>()
        var staleHashes = Set<String>()
        var reusedComicCount = 0

        try database.withConnection(readOnly: false) { database in
            try sqliteBeginTransaction(database: database)
            do {
                let existingFolders = try loadExistingFolders(libraryID: libraryID, database: database)
                let rootFolderID = try upsertFolder(
                    libraryID: libraryID,
                    relativePath: "",
                    parentID: nil,
                    name: "root",
                    existingID: existingFolders[""],
                    database: database
                )

                var folderIDsByPath: [String: Int64] = ["": rootFolderID]
                for folder in discovery.folders where !folder.relativePath.isEmpty {
                    try cancellationCheck?()
                    let parentID = folder.parentRelativePath.flatMap { folderIDsByPath[$0] } ?? rootFolderID
                    let folderID = try upsertFolder(
                        libraryID: libraryID,
                        relativePath: folder.relativePath,
                        parentID: parentID,
                        name: folder.name,
                        existingID: existingFolders[folder.relativePath],
                        database: database
                    )
                    folderIDsByPath[folder.relativePath] = folderID
                }

                let existingComicRecords = try loadExistingComicRecords(libraryID: libraryID, database: database)
                let existingByPath = Dictionary(uniqueKeysWithValues: existingComicRecords.map { ($0.relativePath, $0) })
                let existingByHash = Dictionary(grouping: existingComicRecords, by: \.hash)
                var consumedComicIDs = Set<Int64>()

                for comic in discovery.comics {
                    try cancellationCheck?()

                    let parentFolderID = folderIDsByPath[comic.parentRelativePath] ?? rootFolderID
                    let matchedRecord: ExistingComicRecord? = {
                        if let byPath = existingByPath[comic.relativePath], !consumedComicIDs.contains(byPath.id) {
                            return byPath
                        }

                        return existingByHash[comic.hash]?.first(where: { !consumedComicIDs.contains($0.id) })
                    }()

                    if let matchedRecord {
                        reusedComicCount += 1
                        consumedComicIDs.insert(matchedRecord.id)
                        if matchedRecord.hash != comic.hash {
                            staleHashes.insert(matchedRecord.hash)
                        }
                        try updateComic(
                            recordID: matchedRecord.id,
                            parentFolderID: parentFolderID,
                            scannedComic: comic,
                            database: database
                        )
                    } else {
                        try insertComic(
                            libraryID: libraryID,
                            parentFolderID: parentFolderID,
                            scannedComic: comic,
                            database: database
                        )
                    }

                    currentHashes.insert(comic.hash)
                    if let coverImage = comic.metadata?.coverImage,
                       let coverURL = try? assetStore.plannedCoverURL(hash: comic.hash, libraryID: libraryID) {
                        try metadataExtractor.saveCover(coverImage, to: coverURL)
                    }
                }

                for record in existingComicRecords where !consumedComicIDs.contains(record.id) {
                    staleHashes.insert(record.hash)
                    try deleteComic(id: record.id, database: database)
                }

                let missingFolderRecords = existingFolders
                    .filter { key, _ in !currentFolderPaths.contains(key) && !key.isEmpty }
                    .sorted { lhs, rhs in
                        lhs.key.split(separator: "/").count > rhs.key.split(separator: "/").count
                    }

                for (_, folderID) in missingFolderRecords {
                    try deleteFolder(id: folderID, database: database)
                }

                try refreshFolderMetadata(
                    folders: discovery.folders,
                    comics: discovery.comics,
                    folderIDsByPath: folderIDsByPath,
                    database: database
                )

                try sqliteCommitTransaction(database: database)
            } catch {
                sqliteRollbackTransaction(database: database)
                throw error
            }
        }

        for hash in staleHashes where !currentHashes.contains(hash) {
            assetStore.deleteCover(hash: hash, libraryID: libraryID)
        }

        return LibraryScanSummary(
            folderCount: max(0, discovery.folders.count - 1),
            comicCount: discovery.comics.count,
            previousFolderCount: previousCounts.folderCount,
            previousComicCount: previousCounts.comicCount,
            reusedComicCount: reusedComicCount
        )
    }

    private func currentCounts(for libraryID: UUID) throws -> (folderCount: Int, comicCount: Int) {
        try database.withConnection(readOnly: true) { database in
            let folderCount = try count(
                sql: "SELECT COUNT(*) FROM folders WHERE library_id = ? AND relative_path <> ''",
                bindText: libraryID.uuidString,
                database: database
            )
            let comicCount = try count(
                sql: "SELECT COUNT(*) FROM comics WHERE library_id = ?",
                bindText: libraryID.uuidString,
                database: database
            )
            return (folderCount, comicCount)
        }
    }

    private func loadExistingFolders(
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> [String: Int64] {
        let sql = "SELECT relative_path, id FROM folders WHERE library_id = ?"
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(libraryID.uuidString, index: 1, statement: statement)

        var results: [String: Int64] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            results[sqliteString(statement, index: 0) ?? ""] = sqlite3_column_int64(statement, 1)
        }
        return results
    }

    private func loadExistingComicRecords(
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> [ExistingComicRecord] {
        let sql = "SELECT id, relative_path, file_hash FROM comics WHERE library_id = ?"
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(libraryID.uuidString, index: 1, statement: statement)

        var results: [ExistingComicRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(
                ExistingComicRecord(
                    id: sqlite3_column_int64(statement, 0),
                    relativePath: sqliteString(statement, index: 1) ?? "",
                    hash: sqliteString(statement, index: 2) ?? ""
                )
            )
        }
        return results
    }

    private func upsertFolder(
        libraryID: UUID,
        relativePath: String,
        parentID: Int64?,
        name: String,
        existingID: Int64?,
        database: OpaquePointer
    ) throws -> Int64 {
        let now = Date()

        if let existingID {
            let sql = """
            UPDATE folders
            SET parent_id = ?, name = ?, updated_at = ?
            WHERE id = ?
            """
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            if let parentID {
                sqlite3_bind_int64(statement, 1, parentID)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqliteBindText(name, index: 2, statement: statement)
            sqliteBindDate(now, index: 3, statement: statement)
            sqlite3_bind_int64(statement, 4, existingID)
            try sqliteStepDone(statement, database: database)
            return existingID
        }

        let sql = """
        INSERT INTO folders (stable_id, library_id, parent_id, name, relative_path, file_type, added_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(UUID().uuidString, index: 1, statement: statement)
        sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
        if let parentID {
            sqlite3_bind_int64(statement, 3, parentID)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqliteBindText(name, index: 4, statement: statement)
        sqliteBindText(relativePath, index: 5, statement: statement)
        sqlite3_bind_int64(statement, 6, Int64(LibraryFileType.comic.rawValue))
        sqliteBindDate(now, index: 7, statement: statement)
        sqliteBindDate(now, index: 8, statement: statement)
        try sqliteStepDone(statement, database: database)
        return sqlite3_last_insert_rowid(database)
    }

    private func updateComic(
        recordID: Int64,
        parentFolderID: Int64,
        scannedComic: ScannedComic,
        database: OpaquePointer
    ) throws {
        let sql = """
        UPDATE comics
        SET parent_folder_id = ?,
            file_name = ?,
            relative_path = ?,
            file_hash = ?,
            page_count = COALESCE(?, page_count),
            cover_size_ratio = COALESCE(?, cover_size_ratio),
            updated_at = ?
        WHERE id = ?
        """
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, parentFolderID)
        sqliteBindText(scannedComic.fileName, index: 2, statement: statement)
        sqliteBindText(scannedComic.relativePath, index: 3, statement: statement)
        sqliteBindText(scannedComic.hash, index: 4, statement: statement)
        if let pageCount = scannedComic.metadata?.pageCount {
            sqlite3_bind_int64(statement, 5, Int64(pageCount))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        if let coverSizeRatio = scannedComic.metadata?.coverSizeRatio {
            sqlite3_bind_double(statement, 6, coverSizeRatio)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqliteBindDate(Date(), index: 7, statement: statement)
        sqlite3_bind_int64(statement, 8, recordID)
        try sqliteStepDone(statement, database: database)
    }

    private func insertComic(
        libraryID: UUID,
        parentFolderID: Int64,
        scannedComic: ScannedComic,
        database: OpaquePointer
    ) throws {
        let imported = scannedComic.metadata?.importedComicInfo
        let fileType = imported?.type ?? .comic
        let now = Date()
        let sql = """
        INSERT INTO comics (
            stable_id, library_id, parent_folder_id, file_name, relative_path, file_hash,
            title, issue_number, current_page, page_count, bookmark1, bookmark2, bookmark3,
            is_read, has_been_opened, cover_size_ratio, last_opened_at, added_at, file_type,
            series, volume, rating, is_favorite, story_arc, publication_date, publisher,
            imprint, format, language_iso, writer, penciller, inker, colorist, letterer,
            cover_artist, editor, synopsis, notes, review, tags_text, characters, teams,
            locations, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        sqliteBindText(UUID().uuidString, index: 1, statement: statement)
        sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, parentFolderID)
        sqliteBindText(scannedComic.fileName, index: 4, statement: statement)
        sqliteBindText(scannedComic.relativePath, index: 5, statement: statement)
        sqliteBindText(scannedComic.hash, index: 6, statement: statement)
        sqliteBindOptionalText(imported?.title, index: 7, statement: statement)
        sqliteBindOptionalText(imported?.issueNumber, index: 8, statement: statement)
        sqlite3_bind_int64(statement, 9, 1)
        if let pageCount = scannedComic.metadata?.pageCount {
            sqlite3_bind_int64(statement, 10, Int64(pageCount))
        } else {
            sqlite3_bind_null(statement, 10)
        }
        sqlite3_bind_int64(statement, 11, -1)
        sqlite3_bind_int64(statement, 12, -1)
        sqlite3_bind_int64(statement, 13, -1)
        sqlite3_bind_int(statement, 14, 0)
        sqlite3_bind_int(statement, 15, 0)
        if let coverSizeRatio = scannedComic.metadata?.coverSizeRatio {
            sqlite3_bind_double(statement, 16, coverSizeRatio)
        } else {
            sqlite3_bind_null(statement, 16)
        }
        sqlite3_bind_null(statement, 17)
        sqliteBindDate(now, index: 18, statement: statement)
        sqlite3_bind_int64(statement, 19, Int64(fileType.rawValue))
        sqliteBindOptionalText(imported?.series, index: 20, statement: statement)
        sqliteBindOptionalText(imported?.volume, index: 21, statement: statement)
        sqlite3_bind_null(statement, 22)
        sqlite3_bind_int(statement, 23, 0)
        sqliteBindOptionalText(imported?.storyArc, index: 24, statement: statement)
        sqliteBindOptionalText(imported?.publicationDate, index: 25, statement: statement)
        sqliteBindOptionalText(imported?.publisher, index: 26, statement: statement)
        sqliteBindOptionalText(imported?.imprint, index: 27, statement: statement)
        sqliteBindOptionalText(imported?.format, index: 28, statement: statement)
        sqliteBindOptionalText(imported?.languageISO, index: 29, statement: statement)
        sqliteBindOptionalText(imported?.writer, index: 30, statement: statement)
        sqliteBindOptionalText(imported?.penciller, index: 31, statement: statement)
        sqliteBindOptionalText(imported?.inker, index: 32, statement: statement)
        sqliteBindOptionalText(imported?.colorist, index: 33, statement: statement)
        sqliteBindOptionalText(imported?.letterer, index: 34, statement: statement)
        sqliteBindOptionalText(imported?.coverArtist, index: 35, statement: statement)
        sqliteBindOptionalText(imported?.editor, index: 36, statement: statement)
        sqliteBindOptionalText(imported?.synopsis, index: 37, statement: statement)
        sqliteBindOptionalText(imported?.notes, index: 38, statement: statement)
        sqliteBindOptionalText(imported?.review, index: 39, statement: statement)
        sqliteBindOptionalText(imported?.tags, index: 40, statement: statement)
        sqliteBindOptionalText(imported?.characters, index: 41, statement: statement)
        sqliteBindOptionalText(imported?.teams, index: 42, statement: statement)
        sqliteBindOptionalText(imported?.locations, index: 43, statement: statement)
        sqliteBindDate(now, index: 44, statement: statement)
        sqliteBindDate(now, index: 45, statement: statement)
        try sqliteStepDone(statement, database: database)
    }

    private func deleteComic(id: Int64, database: OpaquePointer) throws {
        let statement = try sqlitePrepare("DELETE FROM comics WHERE id = ?", database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try sqliteStepDone(statement, database: database)
    }

    private func deleteFolder(id: Int64, database: OpaquePointer) throws {
        let statement = try sqlitePrepare("DELETE FROM folders WHERE id = ?", database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try sqliteStepDone(statement, database: database)
    }

    private func refreshFolderMetadata(
        folders: [ScannedFolder],
        comics: [ScannedComic],
        folderIDsByPath: [String: Int64],
        database: OpaquePointer
    ) throws {
        var childFoldersByParent: [String: [ScannedFolder]] = [:]
        for folder in folders where !folder.relativePath.isEmpty {
            childFoldersByParent[folder.parentRelativePath ?? "", default: []].append(folder)
        }
        childFoldersByParent = childFoldersByParent.mapValues { value in
            value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        var comicsByParent: [String: [ScannedComic]] = [:]
        for comic in comics {
            comicsByParent[comic.parentRelativePath, default: []].append(comic)
        }
        comicsByParent = comicsByParent.mapValues { value in
            value.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        }

        func firstHash(for relativePath: String) throws -> String? {
            let directComics = comicsByParent[relativePath] ?? []
            let directChildFolders = childFoldersByParent[relativePath] ?? []
            let firstComicHash = directComics.first?.hash
            var firstChildHash: String?
            for childFolder in directChildFolders {
                if let childHash = try firstHash(for: childFolder.relativePath) {
                    firstChildHash = childHash
                    break
                }
            }
            let directChildrenCount = directComics.count + directChildFolders.count

            if let folderID = folderIDsByPath[relativePath] {
                try updateFolderMetadataRow(
                    folderID: folderID,
                    directChildrenCount: directChildrenCount,
                    firstChildHash: firstComicHash ?? firstChildHash,
                    database: database
                )
            }

            return firstComicHash ?? firstChildHash
        }

        _ = try firstHash(for: "")
    }

    private func updateFolderMetadataRow(
        folderID: Int64,
        directChildrenCount: Int,
        firstChildHash: String?,
        database: OpaquePointer
    ) throws {
        let sql = """
        UPDATE folders
        SET num_children = ?, first_child_hash = ?, updated_at = ?
        WHERE id = ?
        """

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(directChildrenCount))
        sqliteBindOptionalText(firstChildHash, index: 2, statement: statement)
        sqliteBindDate(Date(), index: 3, statement: statement)
        sqlite3_bind_int64(statement, 4, folderID)
        try sqliteStepDone(statement, database: database)
    }

    private func count(
        sql: String,
        bindText: String,
        database: OpaquePointer
    ) throws -> Int {
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(bindText, index: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NativeLibraryStorageError.executionFailed(sqliteLastError(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func shouldIgnoreDirectoryComponent(named name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix(".")
            || lowered == ".yacreaderlibrary"
            || lowered.hasPrefix(".yacreader")
    }

    private func makeRelativePath(for itemURL: URL, sourceRootURL: URL) -> String {
        let rootPath = sourceRootURL.path
        let fullPath = itemURL.path
        guard fullPath.hasPrefix(rootPath) else {
            return itemURL.lastPathComponent
        }

        let relativePath = String(fullPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath
    }

    private func relativeDirectoryPath(for relativePath: String) -> String? {
        let trimmedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else {
            return nil
        }

        let components = trimmedPath.split(separator: "/")
        guard components.count > 1 else {
            return ""
        }

        return components.dropLast().joined(separator: "/")
    }

    private func displayPath(fromRelativePath relativePath: String) -> String {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            return "/"
        }

        return trimmedPath.hasPrefix("/") ? trimmedPath : "/" + trimmedPath
    }

    private func fileFingerprint(for fileURL: URL) throws -> String {
        if let inspection = try directoryImageSequenceInspector.inspectComicDirectory(at: fileURL) {
            return try directoryImageSequenceInspector.fingerprint(for: inspection)
        }

        let size = Int64((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let chunk = try handle.read(upToCount: 512 * 1_024) ?? Data()
        let digest = Insecure.SHA1.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
        return "\(digest)-\(size)"
    }
}
