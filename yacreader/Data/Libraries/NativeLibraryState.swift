import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

final class LibraryStateRepository {
    private let database: AppLibraryDatabase

    init(database: AppLibraryDatabase) {
        self.database = database
    }

    func summary(for contextualDatabaseURL: URL) throws -> LibraryDatabaseSummary {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.ensureInitialized()

        return try database.withConnection(readOnly: true) { database in
            let sql = """
            SELECT
                EXISTS(SELECT 1 FROM folders WHERE library_id = ? LIMIT 1),
                (SELECT COUNT(*) FROM folders WHERE library_id = ? AND relative_path <> ''),
                (SELECT COUNT(*) FROM comics WHERE library_id = ?)
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            let libraryKey = libraryID.uuidString
            sqliteBindText(libraryKey, index: 1, statement: statement)
            sqliteBindText(libraryKey, index: 2, statement: statement)
            sqliteBindText(libraryKey, index: 3, statement: statement)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return LibraryDatabaseSummary()
            }

            let exists = sqlite3_column_int(statement, 0) == 1
            let folderCount = Int(sqlite3_column_int64(statement, 1))
            let comicCount = Int(sqlite3_column_int64(statement, 2))

            return LibraryDatabaseSummary(
                exists: exists,
                version: "AppLibraryV2",
                folderCount: folderCount,
                comicCount: comicCount,
                lastError: nil
            )
        }
    }

    func clearLibraryState(for libraryID: UUID) throws {
        try database.ensureInitialized()
        try database.withConnection(readOnly: false) { database in
            try sqliteBeginTransaction(database: database)
            do {
                let deleteComics = try sqlitePrepare("DELETE FROM comics WHERE library_id = ?", database: database)
                defer { sqlite3_finalize(deleteComics) }
                sqliteBindText(libraryID.uuidString, index: 1, statement: deleteComics)
                try sqliteStepDone(deleteComics, database: database)

                let deleteFolders = try sqlitePrepare("DELETE FROM folders WHERE library_id = ?", database: database)
                defer { sqlite3_finalize(deleteFolders) }
                sqliteBindText(libraryID.uuidString, index: 1, statement: deleteFolders)
                try sqliteStepDone(deleteFolders, database: database)

                let deleteTags = try sqlitePrepare("DELETE FROM tags WHERE library_id = ?", database: database)
                defer { sqlite3_finalize(deleteTags) }
                sqliteBindText(libraryID.uuidString, index: 1, statement: deleteTags)
                try sqliteStepDone(deleteTags, database: database)

                let deleteLists = try sqlitePrepare("DELETE FROM reading_lists WHERE library_id = ?", database: database)
                defer { sqlite3_finalize(deleteLists) }
                sqliteBindText(libraryID.uuidString, index: 1, statement: deleteLists)
                try sqliteStepDone(deleteLists, database: database)

                let deleteScanRuns = try sqlitePrepare("DELETE FROM scan_runs WHERE library_id = ?", database: database)
                defer { sqlite3_finalize(deleteScanRuns) }
                sqliteBindText(libraryID.uuidString, index: 1, statement: deleteScanRuns)
                try sqliteStepDone(deleteScanRuns, database: database)

                try sqliteCommitTransaction(database: database)
            } catch {
                sqliteRollbackTransaction(database: database)
                throw error
            }
        }
    }

    func loadFolderContent(
        databaseURL: URL,
        folderID: Int64 = 1
    ) throws -> LibraryFolderContent {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()

        return try database.withConnection(readOnly: true) { database in
            let resolvedFolderID = try resolveFolderID(folderID, libraryID: libraryID, database: database)
            let folder = try loadFolder(id: resolvedFolderID, libraryID: libraryID, database: database)
            let subfolders = try loadSubfolders(parentID: resolvedFolderID, libraryID: libraryID, database: database)
            let comics = try loadComics(
                sql: """
                SELECT \(comicSelectColumns)
                FROM comics
                WHERE library_id = ? AND parent_folder_id = ?
                ORDER BY COALESCE(NULLIF(TRIM(title), ''), file_name) COLLATE NOCASE, file_name COLLATE NOCASE
                """,
                bindings: { statement in
                    sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
                    sqlite3_bind_int64(statement, 2, resolvedFolderID)
                },
                database: database
            )

            return LibraryFolderContent(folder: folder, subfolders: subfolders, comics: comics)
        }
    }

    func searchLibrary(
        databaseURL: URL,
        query: String,
        limit: Int = 40
    ) throws -> LibrarySearchResults {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return LibrarySearchResults(query: "", folders: [], comics: [])
        }

        let likeQuery = "%\(trimmedQuery)%"
        return try database.withConnection(readOnly: true) { database in
            let folderSQL = """
            SELECT id, parent_id, name, relative_path, finished, completed, num_children, first_child_hash, custom_image, file_type, added_at, updated_at
            FROM folders
            WHERE library_id = ?
              AND relative_path <> ''
              AND (
                    name LIKE ? COLLATE NOCASE
                 OR relative_path LIKE ? COLLATE NOCASE
              )
            ORDER BY name COLLATE NOCASE
            LIMIT ?
            """

            let folderStatement = try sqlitePrepare(folderSQL, database: database)
            defer { sqlite3_finalize(folderStatement) }
            sqliteBindText(libraryID.uuidString, index: 1, statement: folderStatement)
            sqliteBindText(likeQuery, index: 2, statement: folderStatement)
            sqliteBindText(likeQuery, index: 3, statement: folderStatement)
            sqlite3_bind_int64(folderStatement, 4, Int64(max(1, limit)))

            var folders: [LibraryFolder] = []
            while sqlite3_step(folderStatement) == SQLITE_ROW {
                folders.append(folder(from: folderStatement))
            }

            let comics = try loadComics(
                sql: """
                SELECT \(comicSelectColumns)
                FROM comics
                WHERE library_id = ?
                  AND (
                        file_name LIKE ? COLLATE NOCASE
                     OR relative_path LIKE ? COLLATE NOCASE
                     OR title LIKE ? COLLATE NOCASE
                     OR series LIKE ? COLLATE NOCASE
                     OR issue_number LIKE ? COLLATE NOCASE
                  )
                ORDER BY COALESCE(last_opened_at, added_at, created_at) DESC, file_name COLLATE NOCASE
                LIMIT ?
                """,
                bindings: { statement in
                    sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
                    sqliteBindText(likeQuery, index: 2, statement: statement)
                    sqliteBindText(likeQuery, index: 3, statement: statement)
                    sqliteBindText(likeQuery, index: 4, statement: statement)
                    sqliteBindText(likeQuery, index: 5, statement: statement)
                    sqliteBindText(likeQuery, index: 6, statement: statement)
                    sqlite3_bind_int64(statement, 7, Int64(max(1, limit)))
                },
                database: database
            )

            return LibrarySearchResults(query: trimmedQuery, folders: folders, comics: comics)
        }
    }

    func loadSpecialListComics(
        databaseURL: URL,
        kind: LibrarySpecialCollectionKind,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let cutoff = Date().addingTimeInterval(TimeInterval(-max(1, recentDays) * 86_400)).timeIntervalSince1970

        let sql: String
        switch kind {
        case .reading:
            sql = """
            SELECT \(comicSelectColumns)
            FROM comics
            WHERE library_id = ?
              AND has_been_opened = 1
              AND is_read = 0
            ORDER BY last_opened_at DESC, added_at DESC, file_name COLLATE NOCASE\(limitClause)
            """
        case .favorites:
            sql = """
            SELECT \(comicSelectColumns)
            FROM comics
            WHERE library_id = ?
              AND is_favorite = 1
            ORDER BY COALESCE(last_opened_at, added_at, created_at) DESC, file_name COLLATE NOCASE\(limitClause)
            """
        case .recent:
            sql = """
            SELECT \(comicSelectColumns)
            FROM comics
            WHERE library_id = ?
              AND added_at IS NOT NULL
              AND added_at >= ?
            ORDER BY added_at DESC, file_name COLLATE NOCASE\(limitClause)
            """
        }

        return try database.withConnection(readOnly: true) { database in
            try loadComics(
                sql: sql,
                bindings: { statement in
                    sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
                    if kind == .recent {
                        sqlite3_bind_double(statement, 2, cutoff)
                    }
                },
                database: database
            )
        }
    }

    func loadSpecialListCounts(
        databaseURL: URL,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays
    ) throws -> [LibrarySpecialCollectionKind: Int] {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        let cutoff = Date().addingTimeInterval(TimeInterval(-max(1, recentDays) * 86_400)).timeIntervalSince1970

        return try database.withConnection(readOnly: true) { database in
            [
                .reading: try count(
                    sql: """
                    SELECT COUNT(*)
                    FROM comics
                    WHERE library_id = ? AND has_been_opened = 1 AND is_read = 0
                    """,
                    binds: { sqliteBindText(libraryID.uuidString, index: 1, statement: $0) },
                    database: database
                ),
                .favorites: try count(
                    sql: """
                    SELECT COUNT(*)
                    FROM comics
                    WHERE library_id = ? AND is_favorite = 1
                    """,
                    binds: { sqliteBindText(libraryID.uuidString, index: 1, statement: $0) },
                    database: database
                ),
                .recent: try count(
                    sql: """
                    SELECT COUNT(*)
                    FROM comics
                    WHERE library_id = ? AND added_at IS NOT NULL AND added_at >= ?
                    """,
                    binds: {
                        sqliteBindText(libraryID.uuidString, index: 1, statement: $0)
                        sqlite3_bind_double($0, 2, cutoff)
                    },
                    database: database
                ),
            ]
        }
    }

    func loadOrganizationSnapshot(databaseURL: URL) throws -> LibraryOrganizationSnapshot {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        return try database.withConnection(readOnly: true) { database in
            LibraryOrganizationSnapshot(
                labels: try loadCollections(
                    libraryID: libraryID,
                    type: .label,
                    assignedComicID: nil,
                    database: database
                ),
                readingLists: try loadCollections(
                    libraryID: libraryID,
                    type: .readingList,
                    assignedComicID: nil,
                    database: database
                )
            )
        }
    }

    func loadComicOrganizationSnapshot(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryOrganizationSnapshot {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        return try database.withConnection(readOnly: true) { database in
            LibraryOrganizationSnapshot(
                labels: try loadCollections(
                    libraryID: libraryID,
                    type: .label,
                    assignedComicID: comicID,
                    database: database
                ),
                readingLists: try loadCollections(
                    libraryID: libraryID,
                    type: .readingList,
                    assignedComicID: comicID,
                    database: database
                )
            )
        }
    }

    func loadOrganizationComics(
        databaseURL: URL,
        collection: LibraryOrganizationCollection
    ) throws -> [LibraryComic] {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()

        let sql: String
        switch collection.type {
        case .label:
            sql = """
            SELECT \(comicSelectColumns)
            FROM comics
            INNER JOIN comic_tags ON comic_tags.comic_id = comics.id
            WHERE comics.library_id = ?
              AND comic_tags.tag_id = ?
            ORDER BY comic_tags.ordering_index ASC, comics.file_name COLLATE NOCASE
            """
        case .readingList:
            sql = """
            SELECT \(comicSelectColumns)
            FROM comics
            INNER JOIN reading_list_items ON reading_list_items.comic_id = comics.id
            WHERE comics.library_id = ?
              AND reading_list_items.reading_list_id = ?
            ORDER BY reading_list_items.ordering_index ASC, comics.file_name COLLATE NOCASE
            """
        }

        return try database.withConnection(readOnly: true) { database in
            try loadComics(
                sql: sql,
                bindings: { statement in
                    sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
                    sqlite3_bind_int64(statement, 2, collection.id)
                },
                database: database
            )
        }
    }

    func loadAllComics(databaseURL: URL) throws -> [LibraryComic] {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        return try database.withConnection(readOnly: true) { database in
            try loadComics(
                sql: """
                SELECT \(comicSelectColumns)
                FROM comics
                WHERE library_id = ?
                ORDER BY file_name COLLATE NOCASE
                """,
                bindings: { sqliteBindText(libraryID.uuidString, index: 1, statement: $0) },
                database: database
            )
        }
    }

    func loadComicsRecursively(
        databaseURL: URL,
        folderID: Int64
    ) throws -> [LibraryComic] {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        return try database.withConnection(readOnly: true) { database in
            let resolvedFolderID = try resolveFolderID(folderID, libraryID: libraryID, database: database)
            return try loadComics(
                sql: """
                WITH RECURSIVE descendants(id) AS (
                    SELECT id FROM folders WHERE id = ? AND library_id = ?
                    UNION ALL
                    SELECT folders.id
                    FROM folders
                    INNER JOIN descendants ON folders.parent_id = descendants.id
                    WHERE folders.library_id = ?
                )
                SELECT \(comicSelectColumns)
                FROM comics
                WHERE library_id = ?
                  AND parent_folder_id IN (SELECT id FROM descendants)
                ORDER BY file_name COLLATE NOCASE
                """,
                bindings: { statement in
                    sqlite3_bind_int64(statement, 1, resolvedFolderID)
                    sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
                    sqliteBindText(libraryID.uuidString, index: 3, statement: statement)
                    sqliteBindText(libraryID.uuidString, index: 4, statement: statement)
                },
                database: database
            )
        }
    }

    func loadComicMetadata(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryComicMetadata {
        let libraryID = try resolvedLibraryID(from: databaseURL)
        try database.ensureInitialized()
        let sql = """
        SELECT id, file_name, title, series, issue_number, volume, story_arc, publication_date, publisher, imprint, format,
               language_iso, file_type, writer, penciller, inker, colorist, letterer, cover_artist, editor, synopsis,
               notes, review, tags_text, characters, teams, locations
        FROM comics
        WHERE id = ? AND library_id = ?
        LIMIT 1
        """

        return try database.withConnection(readOnly: true) { database in
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, comicID)
            sqliteBindText(libraryID.uuidString, index: 2, statement: statement)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw NativeLibraryStorageError.executionFailed("Comic not found.")
            }

            return LibraryComicMetadata(
                comicID: sqlite3_column_int64(statement, 0),
                fileName: sqliteString(statement, index: 1) ?? "",
                title: sqliteString(statement, index: 2) ?? "",
                series: sqliteString(statement, index: 3) ?? "",
                issueNumber: sqliteString(statement, index: 4) ?? "",
                volume: sqliteString(statement, index: 5) ?? "",
                storyArc: sqliteString(statement, index: 6) ?? "",
                publicationDate: sqliteString(statement, index: 7) ?? "",
                publisher: sqliteString(statement, index: 8) ?? "",
                imprint: sqliteString(statement, index: 9) ?? "",
                format: sqliteString(statement, index: 10) ?? "",
                languageISO: sqliteString(statement, index: 11) ?? "",
                type: LibraryFileType(rawValue: Int(sqlite3_column_int64(statement, 12))) ?? .comic,
                writer: sqliteString(statement, index: 13) ?? "",
                penciller: sqliteString(statement, index: 14) ?? "",
                inker: sqliteString(statement, index: 15) ?? "",
                colorist: sqliteString(statement, index: 16) ?? "",
                letterer: sqliteString(statement, index: 17) ?? "",
                coverArtist: sqliteString(statement, index: 18) ?? "",
                editor: sqliteString(statement, index: 19) ?? "",
                synopsis: sqliteString(statement, index: 20) ?? "",
                notes: sqliteString(statement, index: 21) ?? "",
                review: sqliteString(statement, index: 22) ?? "",
                tags: sqliteString(statement, index: 23) ?? "",
                characters: sqliteString(statement, index: 24) ?? "",
                teams: sqliteString(statement, index: 25) ?? "",
                locations: sqliteString(statement, index: 26) ?? ""
            )
        }
    }

    func updateReadingProgress(
        for comicID: Int64,
        progress: ComicReadingProgress,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureComicBelongs(comicID, libraryID: libraryID, database: database)
            let sql = """
            UPDATE comics
            SET current_page = ?,
                has_been_opened = ?,
                last_opened_at = ?,
                is_read = CASE
                    WHEN ? = 1 THEN 1
                    WHEN is_read = 1 THEN 1
                    ELSE 0
                END,
                page_count = COALESCE(?, page_count),
                updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(progress.currentPage))
            sqlite3_bind_int(statement, 2, progress.hasBeenOpened ? 1 : 0)
            sqlite3_bind_double(statement, 3, progress.lastTimeOpened.timeIntervalSince1970)
            sqlite3_bind_int(statement, 4, progress.read ? 1 : 0)
            if let pageCount = progress.pageCount {
                sqlite3_bind_int64(statement, 5, Int64(pageCount))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqliteBindDate(Date(), index: 6, statement: statement)
            sqlite3_bind_int64(statement, 7, comicID)
            sqliteBindText(libraryID.uuidString, index: 8, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func updateBookmarks(
        for comicID: Int64,
        bookmarkPageIndices: [Int],
        in contextualDatabaseURL: URL
    ) throws {
        let normalizedBookmarks = Array(bookmarkPageIndices.filter { $0 >= 0 }.sorted().prefix(3))
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureComicBelongs(comicID, libraryID: libraryID, database: database)
            let sql = """
            UPDATE comics
            SET bookmark1 = ?, bookmark2 = ?, bookmark3 = ?, updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            for offset in 0..<3 {
                if normalizedBookmarks.indices.contains(offset) {
                    sqlite3_bind_int64(statement, Int32(offset + 1), Int64(normalizedBookmarks[offset]))
                } else {
                    sqlite3_bind_int64(statement, Int32(offset + 1), -1)
                }
            }
            sqliteBindDate(Date(), index: 4, statement: statement)
            sqlite3_bind_int64(statement, 5, comicID)
            sqliteBindText(libraryID.uuidString, index: 6, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        try setFavorite(isFavorite, for: [comicID], in: contextualDatabaseURL)
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicIDs: [Int64],
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard !ids.isEmpty else { return }
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)

        try database.withConnection(readOnly: false) { database in
            try ensureComicsBelong(ids, libraryID: libraryID, database: database)
            let sql = "UPDATE comics SET is_favorite = ?, updated_at = ? WHERE id = ? AND library_id = ?"
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            for comicID in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
                sqliteBindDate(Date(), index: 2, statement: statement)
                sqlite3_bind_int64(statement, 3, comicID)
                sqliteBindText(libraryID.uuidString, index: 4, statement: statement)
                try sqliteStepDone(statement, database: database)
            }
        }
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        try setReadStatus(isRead, for: [comicID], in: contextualDatabaseURL)
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicIDs: [Int64],
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard !ids.isEmpty else { return }
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)

        try database.withConnection(readOnly: false) { database in
            try ensureComicsBelong(ids, libraryID: libraryID, database: database)
            let sql = """
            UPDATE comics
            SET is_read = ?,
                has_been_opened = CASE WHEN ? = 1 THEN 1 ELSE 0 END,
                current_page = CASE
                    WHEN ? = 1 THEN CASE
                        WHEN page_count IS NOT NULL AND page_count > 0 THEN page_count
                        ELSE MAX(current_page, 1)
                    END
                    ELSE 1
                END,
                last_opened_at = CASE WHEN ? = 1 THEN ? ELSE NULL END,
                updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let now = Date()
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            for comicID in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int(statement, 1, isRead ? 1 : 0)
                sqlite3_bind_int(statement, 2, isRead ? 1 : 0)
                sqlite3_bind_int(statement, 3, isRead ? 1 : 0)
                sqlite3_bind_int(statement, 4, isRead ? 1 : 0)
                sqlite3_bind_double(statement, 5, now.timeIntervalSince1970)
                sqliteBindDate(now, index: 6, statement: statement)
                sqlite3_bind_int64(statement, 7, comicID)
                sqliteBindText(libraryID.uuidString, index: 8, statement: statement)
                try sqliteStepDone(statement, database: database)
            }
        }
    }

    func setRating(
        _ rating: Double?,
        for comicID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureComicBelongs(comicID, libraryID: libraryID, database: database)
            let sql = "UPDATE comics SET rating = ?, updated_at = ? WHERE id = ? AND library_id = ?"
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            if let rating {
                sqlite3_bind_double(statement, 1, rating)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqliteBindDate(Date(), index: 2, statement: statement)
            sqlite3_bind_int64(statement, 3, comicID)
            sqliteBindText(libraryID.uuidString, index: 4, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func deleteComics(
        _ comicIDs: [Int64],
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard !ids.isEmpty else { return }
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)

        try database.withConnection(readOnly: false) { database in
            try ensureComicsBelong(ids, libraryID: libraryID, database: database)
            let statement = try sqlitePrepare("DELETE FROM comics WHERE id = ? AND library_id = ?", database: database)
            defer { sqlite3_finalize(statement) }
            for comicID in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, comicID)
                sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
                try sqliteStepDone(statement, database: database)
            }
        }
    }

    func createLabel(
        named name: String,
        color: LibraryLabelColor,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            let sql = """
            INSERT INTO tags (stable_id, library_id, name, color_name, color_ordering, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            let now = Date()
            sqliteBindText(UUID().uuidString, index: 1, statement: statement)
            sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
            sqliteBindText(name.trimmingCharacters(in: .whitespacesAndNewlines), index: 3, statement: statement)
            sqliteBindText(color.databaseName, index: 4, statement: statement)
            sqlite3_bind_int64(statement, 5, Int64(color.rawValue))
            sqliteBindDate(now, index: 6, statement: statement)
            sqliteBindDate(now, index: 7, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func createReadingList(
        named name: String,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        let nextOrdering = try nextReadingListOrdering(libraryID: libraryID)

        try database.withConnection(readOnly: false) { database in
            let sql = """
            INSERT INTO reading_lists (stable_id, library_id, name, ordering_index, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            let now = Date()
            sqliteBindText(UUID().uuidString, index: 1, statement: statement)
            sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
            sqliteBindText(name.trimmingCharacters(in: .whitespacesAndNewlines), index: 3, statement: statement)
            sqlite3_bind_int64(statement, 4, Int64(nextOrdering))
            sqliteBindDate(now, index: 5, statement: statement)
            sqliteBindDate(now, index: 6, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func updateLabel(
        id: Int64,
        named name: String,
        color: LibraryLabelColor,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureTagBelongs(id, libraryID: libraryID, database: database)
            let sql = """
            UPDATE tags
            SET name = ?, color_name = ?, color_ordering = ?, updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            sqliteBindText(name.trimmingCharacters(in: .whitespacesAndNewlines), index: 1, statement: statement)
            sqliteBindText(color.databaseName, index: 2, statement: statement)
            sqlite3_bind_int64(statement, 3, Int64(color.rawValue))
            sqliteBindDate(Date(), index: 4, statement: statement)
            sqlite3_bind_int64(statement, 5, id)
            sqliteBindText(libraryID.uuidString, index: 6, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func updateReadingList(
        id: Int64,
        named name: String,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureReadingListBelongs(id, libraryID: libraryID, database: database)
            let sql = """
            UPDATE reading_lists
            SET name = ?, updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            sqliteBindText(name.trimmingCharacters(in: .whitespacesAndNewlines), index: 1, statement: statement)
            sqliteBindDate(Date(), index: 2, statement: statement)
            sqlite3_bind_int64(statement, 3, id)
            sqliteBindText(libraryID.uuidString, index: 4, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func deleteLabel(
        id: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try deleteCollectionRow(
            tableName: "tags",
            entityName: "label",
            id: id,
            libraryID: libraryID
        )
    }

    func deleteReadingList(
        id: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try deleteCollectionRow(
            tableName: "reading_lists",
            entityName: "reading list",
            id: id,
            libraryID: libraryID
        )
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicID: Int64,
        labelID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        try setLabelMembership(isMember, comicIDs: [comicID], labelID: labelID, in: contextualDatabaseURL)
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        labelID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard !ids.isEmpty else { return }
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)

        try database.withConnection(readOnly: false) { database in
            try ensureTagBelongs(labelID, libraryID: libraryID, database: database)
            try ensureComicsBelong(ids, libraryID: libraryID, database: database)

            if isMember {
                let nextOrdering = try count(
                    sql: """
                    SELECT COUNT(*)
                    FROM comic_tags
                    INNER JOIN tags ON tags.id = comic_tags.tag_id
                    INNER JOIN comics ON comics.id = comic_tags.comic_id
                    WHERE comic_tags.tag_id = ?
                      AND tags.library_id = ?
                      AND comics.library_id = ?
                    """,
                    binds: {
                        sqlite3_bind_int64($0, 1, labelID)
                        sqliteBindText(libraryID.uuidString, index: 2, statement: $0)
                        sqliteBindText(libraryID.uuidString, index: 3, statement: $0)
                    },
                    database: database
                )

                let statement = try sqlitePrepare(
                    "INSERT OR IGNORE INTO comic_tags (tag_id, comic_id, ordering_index) VALUES (?, ?, ?)",
                    database: database
                )
                defer { sqlite3_finalize(statement) }

                var ordering = nextOrdering
                for comicID in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, labelID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    sqlite3_bind_int64(statement, 3, Int64(ordering))
                    try sqliteStepDone(statement, database: database)
                    ordering += 1
                }
            } else {
                let statement = try sqlitePrepare(
                    "DELETE FROM comic_tags WHERE tag_id = ? AND comic_id = ?",
                    database: database
                )
                defer { sqlite3_finalize(statement) }

                for comicID in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, labelID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    try sqliteStepDone(statement, database: database)
                }
            }
        }
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicID: Int64,
        readingListID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        try setReadingListMembership(isMember, comicIDs: [comicID], readingListID: readingListID, in: contextualDatabaseURL)
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        readingListID: Int64,
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard !ids.isEmpty else { return }
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)

        try database.withConnection(readOnly: false) { database in
            try ensureReadingListBelongs(readingListID, libraryID: libraryID, database: database)
            try ensureComicsBelong(ids, libraryID: libraryID, database: database)

            if isMember {
                let nextOrdering = try count(
                    sql: """
                    SELECT COUNT(*)
                    FROM reading_list_items
                    INNER JOIN reading_lists ON reading_lists.id = reading_list_items.reading_list_id
                    INNER JOIN comics ON comics.id = reading_list_items.comic_id
                    WHERE reading_list_items.reading_list_id = ?
                      AND reading_lists.library_id = ?
                      AND comics.library_id = ?
                    """,
                    binds: {
                        sqlite3_bind_int64($0, 1, readingListID)
                        sqliteBindText(libraryID.uuidString, index: 2, statement: $0)
                        sqliteBindText(libraryID.uuidString, index: 3, statement: $0)
                    },
                    database: database
                )

                let statement = try sqlitePrepare(
                    "INSERT OR IGNORE INTO reading_list_items (reading_list_id, comic_id, ordering_index) VALUES (?, ?, ?)",
                    database: database
                )
                defer { sqlite3_finalize(statement) }

                var ordering = nextOrdering
                for comicID in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, readingListID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    sqlite3_bind_int64(statement, 3, Int64(ordering))
                    try sqliteStepDone(statement, database: database)
                    ordering += 1
                }
            } else {
                let statement = try sqlitePrepare(
                    "DELETE FROM reading_list_items WHERE reading_list_id = ? AND comic_id = ?",
                    database: database
                )
                defer { sqlite3_finalize(statement) }

                for comicID in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, readingListID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    try sqliteStepDone(statement, database: database)
                }
            }
        }
    }

    func updateComicMetadata(
        _ metadata: LibraryComicMetadata,
        in contextualDatabaseURL: URL
    ) throws {
        let libraryID = try resolvedLibraryID(from: contextualDatabaseURL)
        try database.withConnection(readOnly: false) { database in
            try ensureComicBelongs(metadata.comicID, libraryID: libraryID, database: database)
            let sql = """
            UPDATE comics
            SET title = ?,
                series = ?,
                issue_number = ?,
                volume = ?,
                story_arc = ?,
                publication_date = ?,
                publisher = ?,
                imprint = ?,
                format = ?,
                language_iso = ?,
                file_type = ?,
                writer = ?,
                penciller = ?,
                inker = ?,
                colorist = ?,
                letterer = ?,
                cover_artist = ?,
                editor = ?,
                synopsis = ?,
                notes = ?,
                review = ?,
                tags_text = ?,
                characters = ?,
                teams = ?,
                locations = ?,
                updated_at = ?
            WHERE id = ? AND library_id = ?
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            sqliteBindOptionalText(metadata.title, index: 1, statement: statement)
            sqliteBindOptionalText(metadata.series, index: 2, statement: statement)
            sqliteBindOptionalText(metadata.issueNumber, index: 3, statement: statement)
            sqliteBindOptionalText(metadata.volume, index: 4, statement: statement)
            sqliteBindOptionalText(metadata.storyArc, index: 5, statement: statement)
            sqliteBindOptionalText(metadata.publicationDate, index: 6, statement: statement)
            sqliteBindOptionalText(metadata.publisher, index: 7, statement: statement)
            sqliteBindOptionalText(metadata.imprint, index: 8, statement: statement)
            sqliteBindOptionalText(metadata.format, index: 9, statement: statement)
            sqliteBindOptionalText(metadata.languageISO, index: 10, statement: statement)
            sqlite3_bind_int64(statement, 11, Int64(metadata.type.rawValue))
            sqliteBindOptionalText(metadata.writer, index: 12, statement: statement)
            sqliteBindOptionalText(metadata.penciller, index: 13, statement: statement)
            sqliteBindOptionalText(metadata.inker, index: 14, statement: statement)
            sqliteBindOptionalText(metadata.colorist, index: 15, statement: statement)
            sqliteBindOptionalText(metadata.letterer, index: 16, statement: statement)
            sqliteBindOptionalText(metadata.coverArtist, index: 17, statement: statement)
            sqliteBindOptionalText(metadata.editor, index: 18, statement: statement)
            sqliteBindOptionalText(metadata.synopsis, index: 19, statement: statement)
            sqliteBindOptionalText(metadata.notes, index: 20, statement: statement)
            sqliteBindOptionalText(metadata.review, index: 21, statement: statement)
            sqliteBindOptionalText(metadata.tags, index: 22, statement: statement)
            sqliteBindOptionalText(metadata.characters, index: 23, statement: statement)
            sqliteBindOptionalText(metadata.teams, index: 24, statement: statement)
            sqliteBindOptionalText(metadata.locations, index: 25, statement: statement)
            sqliteBindDate(Date(), index: 26, statement: statement)
            sqlite3_bind_int64(statement, 27, metadata.comicID)
            sqliteBindText(libraryID.uuidString, index: 28, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func updateComicMetadata(
        _ patch: BatchComicMetadataPatch,
        for comicIDs: [Int64],
        in contextualDatabaseURL: URL
    ) throws {
        let ids = Array(Set(comicIDs))
        guard patch.hasChanges, !ids.isEmpty else { return }

        for comicID in ids {
            var metadata = try loadComicMetadata(databaseURL: contextualDatabaseURL, comicID: comicID)
            if patch.shouldUpdateType { metadata.type = patch.type }
            if patch.shouldUpdateSeries { metadata.series = patch.series }
            if patch.shouldUpdateVolume { metadata.volume = patch.volume }
            if patch.shouldUpdateStoryArc { metadata.storyArc = patch.storyArc }
            if patch.shouldUpdatePublisher { metadata.publisher = patch.publisher }
            if patch.shouldUpdateLanguageISO { metadata.languageISO = patch.languageISO }
            if patch.shouldUpdateFormat { metadata.format = patch.format }
            if patch.shouldUpdateTags { metadata.tags = patch.tags }
            try updateComicMetadata(metadata, in: contextualDatabaseURL)
            if patch.shouldUpdateRating {
                let normalizedRating = min(max(patch.rating, 0), 5)
                try setRating(normalizedRating > 0 ? Double(normalizedRating) : nil, for: comicID, in: contextualDatabaseURL)
            }
        }
    }

    func applyImportedComicInfo(
        _ metadata: ImportedComicInfoMetadata,
        for comicID: Int64,
        in contextualDatabaseURL: URL,
        policy: ComicInfoImportPolicy = .overwriteExisting
    ) throws {
        var currentMetadata = try loadComicMetadata(databaseURL: contextualDatabaseURL, comicID: comicID)
        currentMetadata.applyImportedComicInfo(metadata, policy: policy)
        try updateComicMetadata(currentMetadata, in: contextualDatabaseURL)
    }

    private func resolvedLibraryID(from contextualDatabaseURL: URL) throws -> UUID {
        if let libraryID = database.libraryID(from: contextualDatabaseURL) {
            return libraryID
        }

        throw NativeLibraryStorageError.invalidLibraryContext
    }

    private func ensureComicBelongs(
        _ comicID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws {
        try ensureRowBelongs(
            id: comicID,
            tableName: "comics",
            entityName: "comic",
            libraryID: libraryID,
            database: database
        )
    }

    private func ensureComicsBelong(
        _ comicIDs: [Int64],
        libraryID: UUID,
        database: OpaquePointer
    ) throws {
        let statement = try sqlitePrepare(
            "SELECT 1 FROM comics WHERE id = ? AND library_id = ? LIMIT 1",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        for comicID in comicIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, comicID)
            sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw NativeLibraryStorageError.executionFailed(
                    "One or more comics could not be found in the active library."
                )
            }
        }
    }

    private func ensureTagBelongs(
        _ tagID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws {
        try ensureRowBelongs(
            id: tagID,
            tableName: "tags",
            entityName: "label",
            libraryID: libraryID,
            database: database
        )
    }

    private func ensureReadingListBelongs(
        _ readingListID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws {
        try ensureRowBelongs(
            id: readingListID,
            tableName: "reading_lists",
            entityName: "reading list",
            libraryID: libraryID,
            database: database
        )
    }

    private func ensureRowBelongs(
        id: Int64,
        tableName: String,
        entityName: String,
        libraryID: UUID,
        database: OpaquePointer
    ) throws {
        let sql = "SELECT 1 FROM \(tableName) WHERE id = ? AND library_id = ? LIMIT 1"
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NativeLibraryStorageError.executionFailed(
                "The requested \(entityName) could not be found in the active library."
            )
        }
    }

    private func resolveFolderID(
        _ folderID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> Int64 {
        if folderID > 1,
           let exactFolderID = try existingFolderID(folderID, libraryID: libraryID, database: database) {
            return exactFolderID
        }

        if let rootFolderID = try rootFolderID(libraryID: libraryID, database: database) {
            return rootFolderID
        }

        throw NativeLibraryStorageError.executionFailed("This library has not been indexed yet.")
    }

    private func existingFolderID(
        _ folderID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> Int64? {
        let sql = "SELECT id FROM folders WHERE id = ? AND library_id = ? LIMIT 1"
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, folderID)
        sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func rootFolderID(
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> Int64? {
        let sql = """
        SELECT id
        FROM folders
        WHERE library_id = ? AND parent_id IS NULL
        ORDER BY id ASC
        LIMIT 1
        """

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func loadFolder(
        id: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> LibraryFolder {
        let sql = """
        SELECT id, parent_id, name, relative_path, finished, completed, num_children, first_child_hash, custom_image, file_type, added_at, updated_at
        FROM folders
        WHERE id = ? AND library_id = ?
        LIMIT 1
        """

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        sqliteBindText(libraryID.uuidString, index: 2, statement: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NativeLibraryStorageError.executionFailed("The requested folder could not be found.")
        }

        return folder(from: statement)
    }

    private func loadSubfolders(
        parentID: Int64,
        libraryID: UUID,
        database: OpaquePointer
    ) throws -> [LibraryFolder] {
        let sql = """
        SELECT id, parent_id, name, relative_path, finished, completed, num_children, first_child_hash, custom_image, file_type, added_at, updated_at
        FROM folders
        WHERE library_id = ? AND parent_id = ?
        ORDER BY name COLLATE NOCASE
        """

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
        sqlite3_bind_int64(statement, 2, parentID)

        var folders: [LibraryFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            folders.append(folder(from: statement))
        }

        return folders
    }

    private func loadComics(
        sql: String,
        bindings: (OpaquePointer) -> Void,
        database: OpaquePointer
    ) throws -> [LibraryComic] {
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        bindings(statement)

        var comics: [LibraryComic] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            comics.append(comic(from: statement))
        }

        return comics
    }

    private func loadCollections(
        libraryID: UUID,
        type: LibraryOrganizationCollectionType,
        assignedComicID: Int64?,
        database: OpaquePointer
    ) throws -> [LibraryOrganizationCollection] {
        let sql: String
        switch type {
        case .label:
            sql = """
            SELECT tags.id,
                   tags.name,
                   COUNT(DISTINCT tagged_comics.id),
                   CASE WHEN ? IS NOT NULL AND EXISTS(
                        SELECT 1
                        FROM comic_tags assigned
                        INNER JOIN comics assigned_comics ON assigned_comics.id = assigned.comic_id
                        WHERE assigned.tag_id = tags.id
                          AND assigned.comic_id = ?
                          AND assigned_comics.library_id = tags.library_id
                   ) THEN 1 ELSE 0 END,
                   tags.color_name,
                   tags.color_ordering
            FROM tags
            LEFT JOIN comic_tags ON comic_tags.tag_id = tags.id
            LEFT JOIN comics tagged_comics
                ON tagged_comics.id = comic_tags.comic_id
               AND tagged_comics.library_id = tags.library_id
            WHERE tags.library_id = ?
            GROUP BY tags.id, tags.name, tags.color_name, tags.color_ordering
            ORDER BY tags.color_ordering ASC, tags.name COLLATE NOCASE
            """
        case .readingList:
            sql = """
            SELECT reading_lists.id,
                   reading_lists.name,
                   COUNT(DISTINCT listed_comics.id),
                   CASE WHEN ? IS NOT NULL AND EXISTS(
                        SELECT 1
                        FROM reading_list_items assigned
                        INNER JOIN comics assigned_comics ON assigned_comics.id = assigned.comic_id
                        WHERE assigned.reading_list_id = reading_lists.id
                          AND assigned.comic_id = ?
                          AND assigned_comics.library_id = reading_lists.library_id
                   ) THEN 1 ELSE 0 END,
                   NULL,
                   NULL
            FROM reading_lists
            LEFT JOIN reading_list_items ON reading_list_items.reading_list_id = reading_lists.id
            LEFT JOIN comics listed_comics
                ON listed_comics.id = reading_list_items.comic_id
               AND listed_comics.library_id = reading_lists.library_id
            WHERE reading_lists.library_id = ?
            GROUP BY reading_lists.id, reading_lists.name, reading_lists.ordering_index
            ORDER BY reading_lists.ordering_index ASC, reading_lists.name COLLATE NOCASE
            """
        }

        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        if let assignedComicID {
            sqlite3_bind_int64(statement, 1, assignedComicID)
            sqlite3_bind_int64(statement, 2, assignedComicID)
        } else {
            sqlite3_bind_null(statement, 1)
            sqlite3_bind_null(statement, 2)
        }
        sqliteBindText(libraryID.uuidString, index: 3, statement: statement)

        var collections: [LibraryOrganizationCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let color = LibraryLabelColor(
                databaseColorName: sqliteString(statement, index: 4),
                ordering: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 5)
            )
            collections.append(
                LibraryOrganizationCollection(
                    id: sqlite3_column_int64(statement, 0),
                    name: sqliteString(statement, index: 1) ?? "",
                    type: type,
                    comicCount: Int(sqlite3_column_int64(statement, 2)),
                    isAssigned: sqlite3_column_int(statement, 3) == 1,
                    labelColor: type == .label ? color : nil
                )
            )
        }

        return collections
    }

    private func count(
        sql: String,
        binds: (OpaquePointer) -> Void,
        database: OpaquePointer
    ) throws -> Int {
        let statement = try sqlitePrepare(sql, database: database)
        defer { sqlite3_finalize(statement) }
        binds(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NativeLibraryStorageError.executionFailed(sqliteLastError(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func nextReadingListOrdering(libraryID: UUID) throws -> Int {
        try database.ensureInitialized()
        return try database.withConnection(readOnly: true) { database in
            try count(
                sql: "SELECT COUNT(*) FROM reading_lists WHERE library_id = ?",
                binds: { sqliteBindText(libraryID.uuidString, index: 1, statement: $0) },
                database: database
            )
        }
    }

    private func deleteCollectionRow(
        tableName: String,
        entityName: String,
        id: Int64,
        libraryID: UUID
    ) throws {
        try database.withConnection(readOnly: false) { database in
            try ensureRowBelongs(
                id: id,
                tableName: tableName,
                entityName: entityName,
                libraryID: libraryID,
                database: database
            )

            let statement = try sqlitePrepare(
                "DELETE FROM \(tableName) WHERE id = ? AND library_id = ?",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            sqliteBindText(libraryID.uuidString, index: 2, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    private func folder(from statement: OpaquePointer) -> LibraryFolder {
        let relativePath = sqliteString(statement, index: 3) ?? ""
        return LibraryFolder(
            id: sqlite3_column_int64(statement, 0),
            parentID: sqlite3_column_type(statement, 1) == SQLITE_NULL ? 0 : sqlite3_column_int64(statement, 1),
            name: sqliteString(statement, index: 2) ?? "",
            path: displayPath(fromRelativePath: relativePath),
            finished: sqlite3_column_int(statement, 4) == 1,
            completed: sqlite3_column_int(statement, 5) == 1,
            numChildren: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 6)),
            firstChildHash: sqliteString(statement, index: 7),
            customImage: sqliteString(statement, index: 8),
            type: LibraryFileType(rawValue: Int(sqlite3_column_int64(statement, 9))) ?? .comic,
            addedAt: sqliteDate(statement, index: 10),
            updatedAt: sqliteDate(statement, index: 11)
        )
    }

    private func comic(from statement: OpaquePointer) -> LibraryComic {
        let bookmarkValues = [
            sqlite3_column_int64(statement, 9),
            sqlite3_column_int64(statement, 10),
            sqlite3_column_int64(statement, 11),
        ]
        .filter { $0 >= 0 }
        .map(Int.init)

        let relativePath = sqliteString(statement, index: 3) ?? ""
        return LibraryComic(
            id: sqlite3_column_int64(statement, 0),
            parentID: sqlite3_column_int64(statement, 1),
            fileName: sqliteString(statement, index: 2) ?? "",
            path: displayPath(fromRelativePath: relativePath),
            hash: sqliteString(statement, index: 4) ?? "",
            title: sqliteString(statement, index: 5),
            issueNumber: sqliteString(statement, index: 6),
            currentPage: Int(sqlite3_column_int64(statement, 7)),
            pageCount: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8)),
            bookmarkPageIndices: bookmarkValues,
            read: sqlite3_column_int(statement, 12) == 1,
            hasBeenOpened: sqlite3_column_int(statement, 13) == 1,
            coverSizeRatio: sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 14),
            lastOpenedAt: sqliteDate(statement, index: 15),
            addedAt: sqliteDate(statement, index: 16),
            type: LibraryFileType(rawValue: Int(sqlite3_column_int64(statement, 17))) ?? .comic,
            series: sqliteString(statement, index: 18),
            volume: sqliteString(statement, index: 19),
            rating: sqlite3_column_type(statement, 20) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 20),
            isFavorite: sqlite3_column_int(statement, 21) == 1
        )
    }

    private var comicSelectColumns: String {
        """
        id,
        parent_folder_id,
        file_name,
        relative_path,
        file_hash,
        title,
        issue_number,
        current_page,
        page_count,
        bookmark1,
        bookmark2,
        bookmark3,
        is_read,
        has_been_opened,
        cover_size_ratio,
        last_opened_at,
        added_at,
        file_type,
        series,
        volume,
        rating,
        is_favorite
        """
    }

    private func displayPath(fromRelativePath relativePath: String) -> String {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty {
            return "/"
        }

        return trimmedPath.hasPrefix("/") ? trimmedPath : "/" + trimmedPath
    }
}
