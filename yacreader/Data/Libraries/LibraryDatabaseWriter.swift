import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

enum LibraryDatabaseWriteError: LocalizedError {
    case sqliteUnavailable
    case databaseMissing
    case incompatibleDatabaseVersion(String)
    case openDatabaseFailed(String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .databaseMissing:
            return "The library database does not exist yet."
        case .incompatibleDatabaseVersion(let reason):
            return reason
        case .openDatabaseFailed(let reason):
            return "Unable to open library database for writing. \(reason)"
        case .updateFailed(let reason):
            return "Unable to update the library database. \(reason)"
        }
    }
}

final class LibraryDatabaseWriter {
    private let fileManager: FileManager
    #if canImport(SQLite3)
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    #endif

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func updateReadingProgress(
        for comicID: Int64,
        progress: ComicReadingProgress,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let sql = """
        UPDATE comic_info
        SET currentPage = ?,
            hasBeenOpened = ?,
            lastTimeOpened = ?,
            read = CASE
                WHEN ? = 1 THEN 1
                WHEN read = 1 THEN 1
                ELSE 0
            END,
            numPages = CASE
                WHEN (numPages IS NULL OR numPages = 0) THEN COALESCE(?, numPages)
                ELSE numPages
            END
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(progress.currentPage))
        sqlite3_bind_int(statement, 2, progress.hasBeenOpened ? 1 : 0)
        sqlite3_bind_int64(statement, 3, Int64(progress.lastTimeOpened.timeIntervalSince1970))
        sqlite3_bind_int(statement, 4, progress.read ? 1 : 0)

        if let pageCount = progress.pageCount {
            sqlite3_bind_int64(statement, 5, Int64(pageCount))
        } else {
            sqlite3_bind_null(statement, 5)
        }

        sqlite3_bind_int64(statement, 6, comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func updateBookmarks(
        for comicID: Int64,
        bookmarkPageIndices: [Int],
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let normalizedBookmarks = Array(
            bookmarkPageIndices
                .filter { $0 >= 0 }
                .sorted()
                .prefix(3)
        )

        let sql = """
        UPDATE comic_info
        SET bookmark1 = ?,
            bookmark2 = ?,
            bookmark3 = ?
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        for offset in 0..<3 {
            if normalizedBookmarks.indices.contains(offset) {
                sqlite3_bind_int64(statement, Int32(offset + 1), Int64(normalizedBookmarks[offset]))
            } else {
                sqlite3_bind_int64(statement, Int32(offset + 1), -1)
            }
        }

        sqlite3_bind_int64(statement, 4, comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        if isFavorite {
            let nextOrdering = try nextFavoriteOrdering(database: database)
            let sql = """
            INSERT OR IGNORE INTO comic_default_reading_list (default_reading_list_id, comic_id, ordering)
            VALUES (1, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, comicID)
            sqlite3_bind_int64(statement, 2, nextOrdering)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        } else {
            let sql = """
            DELETE FROM comic_default_reading_list
            WHERE default_reading_list_id = 1 AND comic_id = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, comicID)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let uniqueComicIDs = uniquePreservingOrder(comicIDs)
        guard !uniqueComicIDs.isEmpty else {
            return
        }

        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            if isFavorite {
                let sql = """
                INSERT OR IGNORE INTO comic_default_reading_list (default_reading_list_id, comic_id, ordering)
                VALUES (1, ?, ?)
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                var nextOrdering = try nextFavoriteOrdering(database: database)
                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, comicID)
                    sqlite3_bind_int64(statement, 2, nextOrdering)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }

                    nextOrdering += 1
                }
            } else {
                let sql = """
                DELETE FROM comic_default_reading_list
                WHERE default_reading_list_id = 1 AND comic_id = ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, comicID)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }
                }
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let sql = """
        UPDATE comic_info
        SET read = ?,
            hasBeenOpened = CASE
                WHEN ? = 1 THEN 1
                ELSE 0
            END,
            currentPage = CASE
                WHEN ? = 1 THEN CASE
                    WHEN numPages IS NOT NULL AND numPages > 0 THEN numPages
                    ELSE MAX(currentPage, 1)
                END
                ELSE 1
            END,
            lastTimeOpened = CASE
                WHEN ? = 1 THEN strftime('%s','now')
                ELSE NULL
            END
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        let readValue = isRead ? 1 : 0
        sqlite3_bind_int(statement, 1, Int32(readValue))
        sqlite3_bind_int(statement, 2, Int32(readValue))
        sqlite3_bind_int(statement, 3, Int32(readValue))
        sqlite3_bind_int(statement, 4, Int32(readValue))
        sqlite3_bind_int64(statement, 5, comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setRating(
        _ rating: Double?,
        for comicID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let sql = """
        UPDATE comic_info
        SET rating = ?
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        let normalizedRating: Double
        if let rating {
            normalizedRating = min(max(rating, 0), 5)
        } else {
            normalizedRating = 0
        }

        sqlite3_bind_double(statement, 1, normalizedRating)
        sqlite3_bind_int64(statement, 2, comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let uniqueComicIDs = uniquePreservingOrder(comicIDs)
        guard !uniqueComicIDs.isEmpty else {
            return
        }

        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let sql = """
        UPDATE comic_info
        SET read = ?,
            hasBeenOpened = CASE
                WHEN ? = 1 THEN 1
                ELSE 0
            END,
            currentPage = CASE
                WHEN ? = 1 THEN CASE
                    WHEN numPages IS NOT NULL AND numPages > 0 THEN numPages
                    ELSE MAX(currentPage, 1)
                END
                ELSE 1
            END,
            lastTimeOpened = CASE
                WHEN ? = 1 THEN strftime('%s','now')
                ELSE NULL
            END
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        try performTransaction(database: database) {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            let readValue = isRead ? 1 : 0
            for comicID in uniqueComicIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int(statement, 1, Int32(readValue))
                sqlite3_bind_int(statement, 2, Int32(readValue))
                sqlite3_bind_int(statement, 3, Int32(readValue))
                sqlite3_bind_int(statement, 4, Int32(readValue))
                sqlite3_bind_int64(statement, 5, comicID)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func deleteComics(
        _ comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let uniqueComicIDs = uniquePreservingOrder(comicIDs)
        guard !uniqueComicIDs.isEmpty else {
            return
        }

        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            let deletionRecords = try loadComicDeletionRecords(
                comicIDs: uniqueComicIDs,
                database: database
            )
            guard !deletionRecords.isEmpty else {
                return
            }

            let resolvedComicIDs = deletionRecords.map(\.comicID)
            let comicInfoIDs = uniquePreservingOrder(deletionRecords.map(\.comicInfoID))

            try deleteRows(
                from: "comic_default_reading_list",
                whereColumn: "comic_id",
                matching: resolvedComicIDs,
                database: database
            )
            try deleteRows(
                from: "comic_reading_list",
                whereColumn: "comic_id",
                matching: resolvedComicIDs,
                database: database
            )
            try deleteRows(
                from: "comic_label",
                whereColumn: "comic_id",
                matching: resolvedComicIDs,
                database: database
            )
            try deleteRows(
                from: "comic",
                whereColumn: "id",
                matching: resolvedComicIDs,
                database: database
            )
            try deleteRows(
                from: "comic_info",
                whereColumn: "id",
                matching: comicInfoIDs,
                database: database
            )

            _ = try refreshFolderMetadata(folderID: 1, database: database)
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func createLabel(
        named name: String,
        color: LibraryLabelColor,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
        INSERT INTO label (name, color, ordering)
        VALUES (?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, trimmedName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, color.databaseName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(statement, 3, Int64(color.rawValue))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func createReadingList(
        named name: String,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextOrdering = try nextTopLevelReadingListOrdering(database: database)
        let sql = """
        INSERT INTO reading_list (name, ordering)
        VALUES (?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, trimmedName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(statement, 2, nextOrdering)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func updateLabel(
        id: Int64,
        named name: String,
        color: LibraryLabelColor,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
        UPDATE label
        SET name = ?,
            color = ?,
            ordering = ?
        WHERE id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, trimmedName, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, color.databaseName, -1, transientDestructor)
        sqlite3_bind_int64(statement, 3, Int64(color.rawValue))
        sqlite3_bind_int64(statement, 4, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func updateReadingList(
        id: Int64,
        named name: String,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = """
        UPDATE reading_list
        SET name = ?
        WHERE id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, trimmedName, -1, transientDestructor)
        sqlite3_bind_int64(statement, 2, id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func deleteLabel(
        id: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            let deleteMembershipSQL = """
            DELETE FROM comic_label
            WHERE label_id = ?
            """
            var deleteMembershipStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, deleteMembershipSQL, -1, &deleteMembershipStatement, nil) == SQLITE_OK,
                  let deleteMembershipStatement
            else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(deleteMembershipStatement)
            }

            sqlite3_bind_int64(deleteMembershipStatement, 1, id)
            guard sqlite3_step(deleteMembershipStatement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            let deleteLabelSQL = """
            DELETE FROM label
            WHERE id = ?
            """
            var deleteLabelStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, deleteLabelSQL, -1, &deleteLabelStatement, nil) == SQLITE_OK,
                  let deleteLabelStatement
            else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(deleteLabelStatement)
            }

            sqlite3_bind_int64(deleteLabelStatement, 1, id)
            guard sqlite3_step(deleteLabelStatement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func deleteReadingList(
        id: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            let deleteMembershipSQL = """
            WITH RECURSIVE descendants(id) AS (
                SELECT id FROM reading_list WHERE id = ?
                UNION ALL
                SELECT child.id
                FROM reading_list child
                INNER JOIN descendants ON child.parentId = descendants.id
            )
            DELETE FROM comic_reading_list
            WHERE reading_list_id IN (SELECT id FROM descendants)
            """
            var deleteMembershipStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, deleteMembershipSQL, -1, &deleteMembershipStatement, nil) == SQLITE_OK,
                  let deleteMembershipStatement
            else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(deleteMembershipStatement)
            }

            sqlite3_bind_int64(deleteMembershipStatement, 1, id)
            guard sqlite3_step(deleteMembershipStatement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            let deleteListSQL = """
            WITH RECURSIVE descendants(id) AS (
                SELECT id FROM reading_list WHERE id = ?
                UNION ALL
                SELECT child.id
                FROM reading_list child
                INNER JOIN descendants ON child.parentId = descendants.id
            )
            DELETE FROM reading_list
            WHERE id IN (SELECT id FROM descendants)
            """
            var deleteListStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, deleteListSQL, -1, &deleteListStatement, nil) == SQLITE_OK,
                  let deleteListStatement
            else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(deleteListStatement)
            }

            sqlite3_bind_int64(deleteListStatement, 1, id)
            guard sqlite3_step(deleteListStatement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicID: Int64,
        labelID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        if isMember {
            let nextOrdering = try nextOrdering(
                database: database,
                sql: "SELECT COUNT(*) FROM comic_label WHERE label_id = ?",
                relationID: labelID
            )
            let sql = """
            INSERT OR IGNORE INTO comic_label (label_id, comic_id, ordering)
            VALUES (?, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, labelID)
            sqlite3_bind_int64(statement, 2, comicID)
            sqlite3_bind_int64(statement, 3, nextOrdering)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        } else {
            let sql = """
            DELETE FROM comic_label
            WHERE label_id = ? AND comic_id = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, labelID)
            sqlite3_bind_int64(statement, 2, comicID)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setLabelMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        labelID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let uniqueComicIDs = uniquePreservingOrder(comicIDs)
        guard !uniqueComicIDs.isEmpty else {
            return
        }

        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            if isMember {
                let sql = """
                INSERT OR IGNORE INTO comic_label (label_id, comic_id, ordering)
                VALUES (?, ?, ?)
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                var nextOrdering = try nextOrdering(
                    database: database,
                    sql: "SELECT COUNT(*) FROM comic_label WHERE label_id = ?",
                    relationID: labelID
                )

                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, labelID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    sqlite3_bind_int64(statement, 3, nextOrdering)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }

                    nextOrdering += 1
                }
            } else {
                let sql = """
                DELETE FROM comic_label
                WHERE label_id = ? AND comic_id = ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, labelID)
                    sqlite3_bind_int64(statement, 2, comicID)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }
                }
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicID: Int64,
        readingListID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        if isMember {
            let nextOrdering = try nextReadingListMembershipOrdering(database: database)
            let sql = """
            INSERT OR IGNORE INTO comic_reading_list (reading_list_id, comic_id, ordering)
            VALUES (?, ?, ?)
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, readingListID)
            sqlite3_bind_int64(statement, 2, comicID)
            sqlite3_bind_int64(statement, 3, nextOrdering)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        } else {
            let sql = """
            DELETE FROM comic_reading_list
            WHERE reading_list_id = ? AND comic_id = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }

            defer {
                sqlite3_finalize(statement)
            }

            sqlite3_bind_int64(statement, 1, readingListID)
            sqlite3_bind_int64(statement, 2, comicID)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func setReadingListMembership(
        _ isMember: Bool,
        comicIDs: [Int64],
        readingListID: Int64,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let uniqueComicIDs = uniquePreservingOrder(comicIDs)
        guard !uniqueComicIDs.isEmpty else {
            return
        }

        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        try performTransaction(database: database) {
            if isMember {
                let sql = """
                INSERT OR IGNORE INTO comic_reading_list (reading_list_id, comic_id, ordering)
                VALUES (?, ?, ?)
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                var nextOrdering = try nextReadingListMembershipOrdering(database: database)
                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, readingListID)
                    sqlite3_bind_int64(statement, 2, comicID)
                    sqlite3_bind_int64(statement, 3, nextOrdering)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }

                    nextOrdering += 1
                }
            } else {
                let sql = """
                DELETE FROM comic_reading_list
                WHERE reading_list_id = ? AND comic_id = ?
                """

                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                    throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                }

                defer {
                    sqlite3_finalize(statement)
                }

                for comicID in uniqueComicIDs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int64(statement, 1, readingListID)
                    sqlite3_bind_int64(statement, 2, comicID)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
                    }
                }
            }
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func updateComicMetadata(
        _ metadata: LibraryComicMetadata,
        in databaseURL: URL
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let sql = """
        UPDATE comic_info
        SET title = ?,
            series = ?,
            number = ?,
            volume = ?,
            storyArc = ?,
            date = ?,
            publisher = ?,
            imprint = ?,
            format = ?,
            languageISO = ?,
            type = ?,
            manga = ?,
            writer = ?,
            penciller = ?,
            inker = ?,
            colorist = ?,
            letterer = ?,
            coverArtist = ?,
            editor = ?,
            synopsis = ?,
            notes = ?,
            review = ?,
            tags = ?,
            characters = ?,
            teams = ?,
            locations = ?,
            edited = 1,
            lastTimeMetadataSet = strftime('%s','now')
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        bindNullableText(metadata.title, at: 1, statement: statement)
        bindNullableText(metadata.series, at: 2, statement: statement)
        bindNullableText(metadata.issueNumber, at: 3, statement: statement)
        bindNullableText(metadata.volume, at: 4, statement: statement)
        bindNullableText(metadata.storyArc, at: 5, statement: statement)
        bindNullableText(metadata.publicationDate, at: 6, statement: statement)
        bindNullableText(metadata.publisher, at: 7, statement: statement)
        bindNullableText(metadata.imprint, at: 8, statement: statement)
        bindNullableText(metadata.format, at: 9, statement: statement)
        bindNullableText(metadata.languageISO, at: 10, statement: statement)
        sqlite3_bind_int64(statement, 11, Int64(metadata.type.rawValue))
        sqlite3_bind_int(statement, 12, metadata.type == .manga || metadata.type == .yonkoma ? 1 : 0)
        bindNullableText(metadata.writer, at: 13, statement: statement)
        bindNullableText(metadata.penciller, at: 14, statement: statement)
        bindNullableText(metadata.inker, at: 15, statement: statement)
        bindNullableText(metadata.colorist, at: 16, statement: statement)
        bindNullableText(metadata.letterer, at: 17, statement: statement)
        bindNullableText(metadata.coverArtist, at: 18, statement: statement)
        bindNullableText(metadata.editor, at: 19, statement: statement)
        bindNullableText(metadata.synopsis, at: 20, statement: statement)
        bindNullableText(metadata.notes, at: 21, statement: statement)
        bindNullableText(metadata.review, at: 22, statement: statement)
        bindNullableText(metadata.tags, at: 23, statement: statement)
        bindNullableText(metadata.characters, at: 24, statement: statement)
        bindNullableText(metadata.teams, at: 25, statement: statement)
        bindNullableText(metadata.locations, at: 26, statement: statement)
        sqlite3_bind_int64(statement, 27, metadata.comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func updateComicMetadata(
        _ patch: BatchComicMetadataPatch,
        for comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        guard patch.hasChanges else {
            return
        }

        let orderedComicIDs = uniquePreservingOrder(comicIDs)
        guard !orderedComicIDs.isEmpty else {
            return
        }

        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        var assignments: [String] = []
        if patch.shouldUpdateType {
            assignments.append("type = ?")
            assignments.append("manga = ?")
        }
        if patch.shouldUpdateRating {
            assignments.append("rating = ?")
        }
        if patch.shouldUpdateSeries {
            assignments.append("series = ?")
        }
        if patch.shouldUpdateVolume {
            assignments.append("volume = ?")
        }
        if patch.shouldUpdateStoryArc {
            assignments.append("storyArc = ?")
        }
        if patch.shouldUpdatePublisher {
            assignments.append("publisher = ?")
        }
        if patch.shouldUpdateLanguageISO {
            assignments.append("languageISO = ?")
        }
        if patch.shouldUpdateFormat {
            assignments.append("format = ?")
        }
        if patch.shouldUpdateTags {
            assignments.append("tags = ?")
        }

        assignments.append("edited = 1")
        assignments.append("lastTimeMetadataSet = strftime('%s','now')")

        let comicIDPlaceholders = Array(repeating: "?", count: orderedComicIDs.count).joined(separator: ", ")
        let sql = """
        UPDATE comic_info
        SET \(assignments.joined(separator: ", "))
        WHERE id IN (
            SELECT comicInfoId FROM comic WHERE id IN (\(comicIDPlaceholders))
        )
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        var parameterIndex: Int32 = 1
        if patch.shouldUpdateType {
            sqlite3_bind_int64(statement, parameterIndex, Int64(patch.type.rawValue))
            parameterIndex += 1
            sqlite3_bind_int(statement, parameterIndex, patch.type == .manga || patch.type == .yonkoma ? 1 : 0)
            parameterIndex += 1
        }
        if patch.shouldUpdateRating {
            let normalizedRating = min(max(patch.rating, 0), 5)
            sqlite3_bind_double(statement, parameterIndex, Double(normalizedRating))
            parameterIndex += 1
        }
        if patch.shouldUpdateSeries {
            bindNullableText(patch.series, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdateVolume {
            bindNullableText(patch.volume, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdateStoryArc {
            bindNullableText(patch.storyArc, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdatePublisher {
            bindNullableText(patch.publisher, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdateLanguageISO {
            bindNullableText(patch.languageISO, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdateFormat {
            bindNullableText(patch.format, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }
        if patch.shouldUpdateTags {
            bindNullableText(patch.tags, at: parameterIndex, statement: statement)
            parameterIndex += 1
        }

        for comicID in orderedComicIDs {
            sqlite3_bind_int64(statement, parameterIndex, comicID)
            parameterIndex += 1
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    func applyImportedComicInfo(
        _ metadata: ImportedComicInfoMetadata,
        for comicID: Int64,
        in databaseURL: URL,
        policy: ComicInfoImportPolicy = .overwriteExisting
    ) throws {
        #if canImport(SQLite3)
        let database = try openDatabase(at: databaseURL)
        defer {
            sqlite3_close(database)
        }

        let assignments = [
            importedTextAssignment(column: "title", policy: policy),
            importedTextAssignment(column: "number", policy: policy),
            importedNumericAssignment(column: "count", policy: policy),
            importedTextAssignment(column: "volume", policy: policy),
            importedTextAssignment(column: "storyArc", policy: policy),
            importedTextAssignment(column: "genere", policy: policy),
            importedTextAssignment(column: "writer", policy: policy),
            importedTextAssignment(column: "penciller", policy: policy),
            importedTextAssignment(column: "inker", policy: policy),
            importedTextAssignment(column: "colorist", policy: policy),
            importedTextAssignment(column: "letterer", policy: policy),
            importedTextAssignment(column: "coverArtist", policy: policy),
            importedTextAssignment(column: "date", policy: policy),
            importedTextAssignment(column: "publisher", policy: policy),
            importedTextAssignment(column: "format", policy: policy),
            importedNumericAssignment(column: "color", policy: policy),
            importedTextAssignment(column: "ageRating", policy: policy),
            importedTextAssignment(column: "synopsis", policy: policy),
            importedTextAssignment(column: "characters", policy: policy),
            importedTextAssignment(column: "notes", policy: policy),
            importedTextAssignment(column: "comicVineID", policy: policy),
            importedNumericAssignment(column: "type", policy: policy, zeroRepresentsMissing: true),
            importedNumericAssignment(column: "manga", policy: policy, zeroRepresentsMissing: true),
            importedTextAssignment(column: "editor", policy: policy),
            importedTextAssignment(column: "imprint", policy: policy),
            importedTextAssignment(column: "teams", policy: policy),
            importedTextAssignment(column: "locations", policy: policy),
            importedTextAssignment(column: "series", policy: policy),
            importedTextAssignment(column: "alternateSeries", policy: policy),
            importedTextAssignment(column: "alternateNumber", policy: policy),
            importedNumericAssignment(column: "alternateCount", policy: policy),
            importedTextAssignment(column: "languageISO", policy: policy),
            importedTextAssignment(column: "seriesGroup", policy: policy),
            importedTextAssignment(column: "mainCharacterOrTeam", policy: policy),
            importedTextAssignment(column: "review", policy: policy),
            importedTextAssignment(column: "tags", policy: policy)
        ]

        let sql = """
        UPDATE comic_info
        SET \(assignments.joined(separator: ",\n            ")),
            lastTimeMetadataSet = strftime('%s','now')
        WHERE id = (SELECT comicInfoId FROM comic WHERE id = ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        bindOptionalText(metadata.title, at: 1, statement: statement)
        bindOptionalText(metadata.issueNumber, at: 2, statement: statement)
        bindNullableInt64(metadata.count.map(Int64.init), at: 3, statement: statement)
        bindOptionalText(metadata.volume, at: 4, statement: statement)
        bindOptionalText(metadata.storyArc, at: 5, statement: statement)
        bindOptionalText(metadata.genre, at: 6, statement: statement)
        bindOptionalText(metadata.writer, at: 7, statement: statement)
        bindOptionalText(metadata.penciller, at: 8, statement: statement)
        bindOptionalText(metadata.inker, at: 9, statement: statement)
        bindOptionalText(metadata.colorist, at: 10, statement: statement)
        bindOptionalText(metadata.letterer, at: 11, statement: statement)
        bindOptionalText(metadata.coverArtist, at: 12, statement: statement)
        bindOptionalText(metadata.publicationDate, at: 13, statement: statement)
        bindOptionalText(metadata.publisher, at: 14, statement: statement)
        bindOptionalText(metadata.format, at: 15, statement: statement)
        bindNullableBool(metadata.isColor, at: 16, statement: statement)
        bindOptionalText(metadata.ageRating, at: 17, statement: statement)
        bindOptionalText(metadata.synopsis, at: 18, statement: statement)
        bindOptionalText(metadata.characters, at: 19, statement: statement)
        bindOptionalText(metadata.notes, at: 20, statement: statement)
        bindOptionalText(metadata.comicVineID, at: 21, statement: statement)

        let importedType = metadata.type.map { Int64($0.rawValue) }
        bindNullableInt64(importedType, at: 22, statement: statement)

        let mangaFlag = metadata.type.map { $0 == .manga ? Int64(1) : Int64(0) }
        bindNullableInt64(mangaFlag, at: 23, statement: statement)

        bindOptionalText(metadata.editor, at: 24, statement: statement)
        bindOptionalText(metadata.imprint, at: 25, statement: statement)
        bindOptionalText(metadata.teams, at: 26, statement: statement)
        bindOptionalText(metadata.locations, at: 27, statement: statement)
        bindOptionalText(metadata.series, at: 28, statement: statement)
        bindOptionalText(metadata.alternateSeries, at: 29, statement: statement)
        bindOptionalText(metadata.alternateNumber, at: 30, statement: statement)
        bindNullableInt64(metadata.alternateCount.map(Int64.init), at: 31, statement: statement)
        bindOptionalText(metadata.languageISO, at: 32, statement: statement)
        bindOptionalText(metadata.seriesGroup, at: 33, statement: statement)
        bindOptionalText(metadata.mainCharacterOrTeam, at: 34, statement: statement)
        bindOptionalText(metadata.review, at: 35, statement: statement)
        bindOptionalText(metadata.tags, at: 36, statement: statement)
        sqlite3_bind_int64(statement, 37, comicID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }
        #else
        throw LibraryDatabaseWriteError.sqliteUnavailable
        #endif
    }

    #if canImport(SQLite3)
    private func nextFavoriteOrdering(database: OpaquePointer) throws -> Int64 {
        let sql = "SELECT COUNT(*) FROM comic_default_reading_list WHERE default_reading_list_id = 1"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func nextTopLevelReadingListOrdering(database: OpaquePointer) throws -> Int64 {
        let sql = "SELECT COUNT(*) FROM reading_list WHERE parentId IS NULL"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func nextReadingListMembershipOrdering(database: OpaquePointer) throws -> Int64 {
        let sql = "SELECT COUNT(*) FROM comic_reading_list"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func nextOrdering(
        database: OpaquePointer,
        sql: String,
        relationID: Int64
    ) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, relationID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        return sqlite3_column_int64(statement, 0)
    }

    private func openDatabase(at databaseURL: URL) throws -> OpaquePointer {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseWriteError.databaseMissing
        }

        let summary = SQLiteDatabaseInspector().inspectDatabase(at: databaseURL)
        guard summary.hasCompatibleSchemaVersion else {
            let versionText = summary.version ?? "Unknown"
            throw LibraryDatabaseWriteError.incompatibleDatabaseVersion(
                "This library uses DB \(versionText), which is not writable from this iOS build."
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
            throw LibraryDatabaseWriteError.openDatabaseFailed(reason)
        }

        return database
    }

    private func loadComicDeletionRecords(
        comicIDs: [Int64],
        database: OpaquePointer
    ) throws -> [(comicID: Int64, comicInfoID: Int64)] {
        let sql = """
        SELECT id, comicInfoId
        FROM comic
        WHERE id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        var results: [(comicID: Int64, comicInfoID: Int64)] = []
        results.reserveCapacity(comicIDs.count)

        for comicID in comicIDs {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, comicID)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                continue
            }

            results.append((
                comicID: sqlite3_column_int64(statement, 0),
                comicInfoID: sqlite3_column_int64(statement, 1)
            ))
        }

        return results
    }

    private func deleteRows(
        from table: String,
        whereColumn: String,
        matching ids: [Int64],
        database: OpaquePointer
    ) throws {
        guard !ids.isEmpty else {
            return
        }

        let sql = "DELETE FROM \(table) WHERE \(whereColumn) = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_int64(statement, 1, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        }
    }

    private func refreshFolderMetadata(
        folderID: Int64,
        database: OpaquePointer
    ) throws -> String? {
        let childFolderIDs = try loadChildFolderIDs(
            parentFolderID: folderID,
            database: database
        )

        var firstChildHashFromSubfolder: String?
        for childFolderID in childFolderIDs {
            let childHash = try refreshFolderMetadata(
                folderID: childFolderID,
                database: database
            )
            if firstChildHashFromSubfolder == nil,
               let childHash,
               !childHash.isEmpty {
                firstChildHashFromSubfolder = childHash
            }
        }

        let comicCount = try loadComicCount(
            parentFolderID: folderID,
            database: database
        )
        let firstComicHash = try loadFirstComicHash(
            parentFolderID: folderID,
            database: database
        )
        let firstChildHash = firstComicHash ?? firstChildHashFromSubfolder
        let childCount = childFolderIDs.count + comicCount

        let sql = "UPDATE folder SET numChildren = ?, firstChildHash = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(childCount))
        bindOptionalText(firstChildHash, at: 2, statement: statement)
        sqlite3_bind_int64(statement, 3, folderID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        return firstChildHash
    }

    private func loadChildFolderIDs(
        parentFolderID: Int64,
        database: OpaquePointer
    ) throws -> [Int64] {
        let sql = """
        SELECT id
        FROM folder
        WHERE parentId = ? AND id <> 1
        ORDER BY name COLLATE NOCASE
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        var results: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(sqlite3_column_int64(statement, 0))
        }

        return results
    }

    private func loadComicCount(
        parentFolderID: Int64,
        database: OpaquePointer
    ) throws -> Int {
        let sql = "SELECT COUNT(*) FROM comic WHERE parentId = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func loadFirstComicHash(
        parentFolderID: Int64,
        database: OpaquePointer
    ) throws -> String? {
        let sql = """
        SELECT ci.hash
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE c.parentId = ?
        ORDER BY c.fileName COLLATE NOCASE
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentFolderID)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        return String(cString: value)
    }

    private func performTransaction(
        database: OpaquePointer,
        body: () throws -> Void
    ) throws {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
        }

        do {
            try body()
            guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw LibraryDatabaseWriteError.updateFailed(lastDatabaseError(database: database))
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func lastDatabaseError(database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }

    private func bindNullableText(_ text: String, at index: Int32, statement: OpaquePointer) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sqlite3_bind_null(statement, index)
        } else {
            sqlite3_bind_text(statement, index, trimmed, -1, transientDestructor)
        }
    }

    private func bindOptionalText(_ text: String?, at index: Int32, statement: OpaquePointer) {
        guard let text else {
            sqlite3_bind_null(statement, index)
            return
        }

        bindNullableText(text, at: index, statement: statement)
    }

    private func bindNullableInt64(_ value: Int64?, at index: Int32, statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_int64(statement, index, value)
    }

    private func bindNullableBool(_ value: Bool?, at index: Int32, statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        sqlite3_bind_int(statement, index, value ? 1 : 0)
    }

    private func importedTextAssignment(
        column: String,
        policy: ComicInfoImportPolicy
    ) -> String {
        switch policy {
        case .overwriteExisting:
            return "\(column) = COALESCE(?, \(column))"
        case .fillMissing:
            return "\(column) = CASE WHEN \(column) IS NULL OR TRIM(\(column)) = '' THEN COALESCE(?, \(column)) ELSE \(column) END"
        }
    }

    private func importedNumericAssignment(
        column: String,
        policy: ComicInfoImportPolicy,
        zeroRepresentsMissing: Bool = false
    ) -> String {
        switch policy {
        case .overwriteExisting:
            return "\(column) = COALESCE(?, \(column))"
        case .fillMissing:
            let missingCondition = zeroRepresentsMissing ? "\(column) IS NULL OR \(column) = 0" : "\(column) IS NULL"
            return "\(column) = CASE WHEN \(missingCondition) THEN COALESCE(?, \(column)) ELSE \(column) END"
        }
    }

    private func uniquePreservingOrder(_ comicIDs: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        var orderedIDs: [Int64] = []
        orderedIDs.reserveCapacity(comicIDs.count)

        for comicID in comicIDs where seen.insert(comicID).inserted {
            orderedIDs.append(comicID)
        }

        return orderedIDs
    }
    #endif
}
