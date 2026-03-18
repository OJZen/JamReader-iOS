import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

enum LibraryDatabaseReadError: LocalizedError {
    case databaseMissing
    case sqliteUnavailable
    case openDatabaseFailed(String)
    case folderNotFound(Int64)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing:
            return "This library does not have a readable library.ydb yet."
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .openDatabaseFailed(let reason):
            return "Unable to open library database. \(reason)"
        case .folderNotFound(let folderID):
            return "The requested folder \(folderID) was not found in library.ydb."
        case .queryFailed(let reason):
            return "Library query failed. \(reason)"
        }
    }
}

final class LibraryDatabaseReader {
    private let fileManager: FileManager
    #if canImport(SQLite3)
    private let favoritesListID: Int64 = 1
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    #endif

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadFolderContent(databaseURL: URL, folderID: Int64 = 1) throws -> LibraryFolderContent {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        let folder = try loadFolder(id: folderID, database: database)
        let subfolders = try loadSubfolders(parentID: folderID, database: database).sorted { lhs, rhs in
            sortFolders(lhs: lhs, rhs: rhs)
        }
        let comics = try loadComics(parentID: folderID, database: database).sorted { lhs, rhs in
            sortComics(lhs: lhs, rhs: rhs)
        }

        return LibraryFolderContent(folder: folder, subfolders: subfolders, comics: comics)
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func searchLibrary(
        databaseURL: URL,
        query: String,
        limit: Int = 40
    ) throws -> LibrarySearchResults {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return LibrarySearchResults(query: "", folders: [], comics: [])
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        let folders = try searchFolders(
            matching: trimmedQuery,
            limit: limit,
            database: database
        )
        let comics = try searchComics(
            matching: trimmedQuery,
            limit: limit,
            database: database
        )

        return LibrarySearchResults(query: trimmedQuery, folders: folders, comics: comics)
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadSpecialListComics(
        databaseURL: URL,
        kind: LibrarySpecialCollectionKind,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        switch kind {
        case .reading:
            return try loadReadingComics(database: database, limit: limit)
        case .favorites:
            return try loadFavoriteComics(database: database, limit: limit)
        case .recent:
            return try loadRecentComics(recentDays: recentDays, database: database, limit: limit)
        }
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadSpecialListCounts(
        databaseURL: URL,
        recentDays: Int = LibrarySpecialCollectionKind.defaultRecentDays
    ) throws -> [LibrarySpecialCollectionKind: Int] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        return [
            .reading: try countReadingComics(database: database),
            .favorites: try countFavoriteComics(database: database),
            .recent: try countRecentComics(recentDays: recentDays, database: database)
        ]
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadOrganizationSnapshot(databaseURL: URL) throws -> LibraryOrganizationSnapshot {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        return LibraryOrganizationSnapshot(
            labels: try loadLabels(assignedComicID: nil, database: database),
            readingLists: try loadReadingLists(assignedComicID: nil, database: database)
        )
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadComicOrganizationSnapshot(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryOrganizationSnapshot {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        return LibraryOrganizationSnapshot(
            labels: try loadLabels(assignedComicID: comicID, database: database),
            readingLists: try loadReadingLists(assignedComicID: comicID, database: database)
        )
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadOrganizationComics(
        databaseURL: URL,
        collection: LibraryOrganizationCollection
    ) throws -> [LibraryComic] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        switch collection.type {
        case .label:
            return try loadLabelComics(labelID: collection.id, database: database)
        case .readingList:
            return try loadReadingListComics(readingListID: collection.id, database: database)
        }
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadAllComics(databaseURL: URL) throws -> [LibraryComic] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        return try loadAllComics(database: database)
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadComicsRecursively(
        databaseURL: URL,
        folderID: Int64
    ) throws -> [LibraryComic] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        _ = try loadFolder(id: folderID, database: database)
        return try loadComicsRecursively(folderID: folderID, database: database)
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    func loadComicMetadata(
        databaseURL: URL,
        comicID: Int64
    ) throws -> LibraryComicMetadata {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseReadError.databaseMissing
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseReadError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        let sql = """
        SELECT
            c.id,
            c.fileName,
            ci.title,
            ci.series,
            ci.number,
            ci.volume,
            ci.storyArc,
            ci.date,
            ci.publisher,
            ci.imprint,
            ci.format,
            ci.languageISO,
            ci.type,
            ci.writer,
            ci.penciller,
            ci.inker,
            ci.colorist,
            ci.letterer,
            ci.coverArtist,
            ci.editor,
            ci.synopsis,
            ci.notes,
            ci.review,
            ci.tags,
            ci.characters,
            ci.teams,
            ci.locations
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE c.id = ?
        LIMIT 1
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, comicID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseReadError.queryFailed("Comic \(comicID) metadata was not found.")
        }

        return makeComicMetadata(from: statement)
        #else
        throw LibraryDatabaseReadError.sqliteUnavailable
        #endif
    }

    #if canImport(SQLite3)
    private var comicProjectionSQL: String {
        """
        c.id,
        c.parentId,
        c.fileName,
        c.path,
        ci.hash,
        ci.title,
        ci.number,
        ci.currentPage,
        ci.numPages,
        ci.bookmark1,
        ci.bookmark2,
        ci.bookmark3,
        ci.read,
        ci.hasBeenOpened,
        ci.coverSizeRatio,
        ci.lastTimeOpened,
        ci.added,
        ci.type,
        ci.series,
        ci.volume,
        ci.rating,
        CASE WHEN fav.comic_id IS NOT NULL THEN 1 ELSE 0 END AS isFavorite
        """
    }

    private var comicBaseJoinSQL: String {
        """
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        LEFT JOIN comic_default_reading_list fav
            ON fav.comic_id = c.id AND fav.default_reading_list_id = \(favoritesListID)
        """
    }

    private func loadFolder(id: Int64, database: OpaquePointer) throws -> LibraryFolder {
        let sql = """
        SELECT id, parentId, name, path, finished, completed, numChildren, firstChildHash, customImage, type, added, updated
        FROM folder
        WHERE id = ?
        LIMIT 1
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseReadError.folderNotFound(id)
        }

        return makeFolder(from: statement)
    }

    private func loadSubfolders(parentID: Int64, database: OpaquePointer) throws -> [LibraryFolder] {
        let sql = """
        SELECT id, parentId, name, path, finished, completed, numChildren, firstChildHash, customImage, type, added, updated
        FROM folder
        WHERE parentId = ? AND id <> 1
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentID)

        var folders: [LibraryFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            folders.append(makeFolder(from: statement))
        }

        return folders
    }

    private func loadComics(parentID: Int64, database: OpaquePointer) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        WHERE c.parentId = ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, parentID)

        var comics: [LibraryComic] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            comics.append(makeComic(from: statement))
        }

        return comics
    }

    private func loadAllComics(database: OpaquePointer) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        ORDER BY
            COALESCE(c.path, c.fileName) COLLATE NOCASE ASC,
            COALESCE(NULLIF(ci.title, ''), c.fileName) COLLATE NOCASE ASC
        """

        return try loadComics(sql: sql, bindings: { _ in }, database: database)
    }

    private func loadComicsRecursively(
        folderID: Int64,
        database: OpaquePointer
    ) throws -> [LibraryComic] {
        let sql = """
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id
            FROM folder
            WHERE id = ?
            UNION ALL
            SELECT f.id
            FROM folder f
            INNER JOIN folder_tree ft ON f.parentId = ft.id
        )
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        WHERE c.parentId IN (SELECT id FROM folder_tree)
        ORDER BY
            COALESCE(c.path, c.fileName) COLLATE NOCASE ASC,
            COALESCE(NULLIF(ci.title, ''), c.fileName) COLLATE NOCASE ASC
        """

        return try loadComics(
            sql: sql,
            bindings: { statement in
                sqlite3_bind_int64(statement, 1, folderID)
            },
            database: database
        )
    }

    private func loadReadingComics(
        database: OpaquePointer,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        WHERE ci.hasBeenOpened = 1 AND ci.read = 0
        ORDER BY ci.lastTimeOpened DESC
        """

        return try loadComics(
            sql: appendLimitClause(to: sql, limit: limit),
            bindings: { _ in },
            database: database
        )
    }

    private func loadFavoriteComics(
        database: OpaquePointer,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        let sql = """
        SELECT
            c.id,
            c.parentId,
            c.fileName,
            c.path,
            ci.hash,
            ci.title,
            ci.number,
            ci.currentPage,
            ci.numPages,
            ci.bookmark1,
            ci.bookmark2,
            ci.bookmark3,
            ci.read,
            ci.hasBeenOpened,
            ci.coverSizeRatio,
            ci.lastTimeOpened,
            ci.added,
            ci.type,
            ci.series,
            ci.volume,
            1 AS isFavorite
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        INNER JOIN comic_default_reading_list cdrl
            ON c.id = cdrl.comic_id AND cdrl.default_reading_list_id = \(favoritesListID)
        ORDER BY cdrl.ordering ASC
        """

        return try loadComics(
            sql: appendLimitClause(to: sql, limit: limit),
            bindings: { _ in },
            database: database
        )
    }

    private func loadRecentComics(
        recentDays: Int,
        database: OpaquePointer,
        limit: Int? = nil
    ) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        WHERE ci.added > ?
        ORDER BY ci.added DESC
        """

        let cutoffTimestamp = Int64(Date().addingTimeInterval(TimeInterval(-max(1, recentDays) * 86_400)).timeIntervalSince1970)
        return try loadComics(
            sql: appendLimitClause(to: sql, limit: limit),
            bindings: { statement in
                sqlite3_bind_int64(statement, 1, cutoffTimestamp)
            },
            database: database
        )
    }

    private func countReadingComics(database: OpaquePointer) throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE ci.hasBeenOpened = 1 AND ci.read = 0
        """

        return try loadCount(sql: sql, bindings: { _ in }, database: database)
    }

    private func countFavoriteComics(database: OpaquePointer) throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM comic_default_reading_list
        WHERE default_reading_list_id = \(favoritesListID)
        """

        return try loadCount(sql: sql, bindings: { _ in }, database: database)
    }

    private func countRecentComics(
        recentDays: Int,
        database: OpaquePointer
    ) throws -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM comic c
        INNER JOIN comic_info ci ON c.comicInfoId = ci.id
        WHERE ci.added > ?
        """

        let cutoffTimestamp = Int64(Date().addingTimeInterval(TimeInterval(-max(1, recentDays) * 86_400)).timeIntervalSince1970)
        return try loadCount(
            sql: sql,
            bindings: { statement in
                sqlite3_bind_int64(statement, 1, cutoffTimestamp)
            },
            database: database
        )
    }

    private func loadLabels(
        assignedComicID: Int64?,
        database: OpaquePointer
    ) throws -> [LibraryOrganizationCollection] {
        let sql = """
        SELECT
            l.id,
            l.name,
            l.color,
            l.ordering,
            COUNT(DISTINCT cl_all.comic_id) AS comicCount,
            MAX(CASE WHEN cl_member.comic_id IS NOT NULL THEN 1 ELSE 0 END) AS isAssigned
        FROM label l
        LEFT JOIN comic_label cl_all
            ON cl_all.label_id = l.id
        LEFT JOIN comic_label cl_member
            ON cl_member.label_id = l.id AND cl_member.comic_id = ?
        GROUP BY l.id, l.name, l.color, l.ordering
        ORDER BY l.ordering ASC, l.name COLLATE NOCASE ASC
        """

        return try loadOrganizationCollections(
            sql: sql,
            collectionType: .label,
            membershipComicID: assignedComicID,
            database: database
        )
    }

    private func loadReadingLists(
        assignedComicID: Int64?,
        database: OpaquePointer
    ) throws -> [LibraryOrganizationCollection] {
        let sql = """
        SELECT
            rl.id,
            rl.name,
            NULL AS color,
            rl.ordering,
            COUNT(DISTINCT crl_all.comic_id) AS comicCount,
            MAX(CASE WHEN crl_member.comic_id IS NOT NULL THEN 1 ELSE 0 END) AS isAssigned
        FROM reading_list rl
        LEFT JOIN comic_reading_list crl_all
            ON crl_all.reading_list_id = rl.id
        LEFT JOIN comic_reading_list crl_member
            ON crl_member.reading_list_id = rl.id AND crl_member.comic_id = ?
        WHERE rl.parentId IS NULL
        GROUP BY rl.id, rl.name, rl.ordering
        ORDER BY rl.name COLLATE NOCASE ASC
        """

        return try loadOrganizationCollections(
            sql: sql,
            collectionType: .readingList,
            membershipComicID: assignedComicID,
            database: database
        )
    }

    private func loadLabelComics(labelID: Int64, database: OpaquePointer) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        INNER JOIN comic_label cl
            ON cl.comic_id = c.id
        WHERE cl.label_id = ?
        ORDER BY cl.ordering ASC, COALESCE(NULLIF(ci.title, ''), c.fileName) COLLATE NOCASE ASC
        """

        return try loadComics(
            sql: sql,
            bindings: { statement in
                sqlite3_bind_int64(statement, 1, labelID)
            },
            database: database
        )
    }

    private func loadReadingListComics(readingListID: Int64, database: OpaquePointer) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        INNER JOIN comic_reading_list crl
            ON crl.comic_id = c.id
        WHERE crl.reading_list_id = ?
        ORDER BY crl.ordering ASC, COALESCE(NULLIF(ci.title, ''), c.fileName) COLLATE NOCASE ASC
        """

        return try loadComics(
            sql: sql,
            bindings: { statement in
                sqlite3_bind_int64(statement, 1, readingListID)
            },
            database: database
        )
    }

    private func loadComics(
        sql: String,
        bindings: (OpaquePointer) -> Void,
        database: OpaquePointer
    ) throws -> [LibraryComic] {
        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        bindings(statement)

        var comics: [LibraryComic] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            comics.append(makeComic(from: statement))
        }

        return comics
    }

    private func loadCount(
        sql: String,
        bindings: (OpaquePointer) -> Void,
        database: OpaquePointer
    ) throws -> Int {
        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LibraryDatabaseReadError.queryFailed(lastDatabaseError(database: database))
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func appendLimitClause(to sql: String, limit: Int?) -> String {
        guard let limit, limit > 0 else {
            return sql
        }

        return "\(sql)\nLIMIT \(limit)"
    }

    private func loadOrganizationCollections(
        sql: String,
        collectionType: LibraryOrganizationCollectionType,
        membershipComicID: Int64?,
        database: OpaquePointer
    ) throws -> [LibraryOrganizationCollection] {
        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, membershipComicID ?? -1)

        var collections: [LibraryOrganizationCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            collections.append(makeOrganizationCollection(from: statement, type: collectionType))
        }

        return collections
    }

    private func searchFolders(
        matching query: String,
        limit: Int,
        database: OpaquePointer
    ) throws -> [LibraryFolder] {
        let sql = """
        SELECT id, parentId, name, path, finished, completed, numChildren, firstChildHash, customImage, type, added, updated
        FROM folder
        WHERE id <> 1
          AND (
            name LIKE ? COLLATE NOCASE
            OR path LIKE ? COLLATE NOCASE
          )
        ORDER BY name COLLATE NOCASE ASC, path COLLATE NOCASE ASC
        LIMIT ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        let likeQuery = "%\(query)%"
        sqlite3_bind_text(statement, 1, likeQuery, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, likeQuery, -1, transientDestructor)
        sqlite3_bind_int64(statement, 3, Int64(max(1, limit)))

        var folders: [LibraryFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            folders.append(makeFolder(from: statement))
        }

        return folders
    }

    private func searchComics(
        matching query: String,
        limit: Int,
        database: OpaquePointer
    ) throws -> [LibraryComic] {
        let sql = """
        SELECT \(comicProjectionSQL)
        \(comicBaseJoinSQL)
        WHERE
            c.fileName LIKE ? COLLATE NOCASE
            OR COALESCE(ci.title, '') LIKE ? COLLATE NOCASE
            OR COALESCE(ci.series, '') LIKE ? COLLATE NOCASE
            OR COALESCE(ci.volume, '') LIKE ? COLLATE NOCASE
            OR COALESCE(ci.number, '') LIKE ? COLLATE NOCASE
            OR COALESCE(c.path, '') LIKE ? COLLATE NOCASE
        ORDER BY
            COALESCE(NULLIF(ci.title, ''), c.fileName) COLLATE NOCASE ASC,
            c.fileName COLLATE NOCASE ASC
        LIMIT ?
        """

        let statement = try prepareStatement(sql, database: database)
        defer {
            sqlite3_finalize(statement)
        }

        let likeQuery = "%\(query)%"
        for parameterIndex in 1...6 {
            sqlite3_bind_text(statement, Int32(parameterIndex), likeQuery, -1, transientDestructor)
        }
        sqlite3_bind_int64(statement, 7, Int64(max(1, limit)))

        var comics: [LibraryComic] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            comics.append(makeComic(from: statement))
        }

        return comics
    }

    private func prepareStatement(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseReadError.queryFailed(lastDatabaseError(database: database))
        }

        return statement
    }

    private func makeFolder(from statement: OpaquePointer) -> LibraryFolder {
        LibraryFolder(
            id: sqlite3_column_int64(statement, 0),
            parentID: sqlite3_column_int64(statement, 1),
            name: stringValue(at: 2, statement: statement) ?? "",
            path: stringValue(at: 3, statement: statement) ?? "",
            finished: boolValue(at: 4, statement: statement),
            completed: boolValue(at: 5, statement: statement),
            numChildren: intValue(at: 6, statement: statement),
            firstChildHash: stringValue(at: 7, statement: statement),
            customImage: stringValue(at: 8, statement: statement),
            type: LibraryFileType(databaseValue: optionalInt64Value(at: 9, statement: statement)),
            addedAt: dateValue(at: 10, statement: statement),
            updatedAt: dateValue(at: 11, statement: statement)
        )
    }

    private func makeComic(from statement: OpaquePointer) -> LibraryComic {
        LibraryComic(
            id: sqlite3_column_int64(statement, 0),
            parentID: sqlite3_column_int64(statement, 1),
            fileName: stringValue(at: 2, statement: statement) ?? "",
            path: stringValue(at: 3, statement: statement),
            hash: stringValue(at: 4, statement: statement) ?? "",
            title: stringValue(at: 5, statement: statement),
            issueNumber: stringValue(at: 6, statement: statement),
            currentPage: intValue(at: 7, statement: statement) ?? 0,
            pageCount: intValue(at: 8, statement: statement),
            bookmarkPageIndices: bookmarkPageIndices(
                statement: statement,
                indices: [9, 10, 11]
            ),
            read: boolValue(at: 12, statement: statement),
            hasBeenOpened: boolValue(at: 13, statement: statement),
            coverSizeRatio: doubleValue(at: 14, statement: statement),
            lastOpenedAt: dateValue(at: 15, statement: statement),
            addedAt: dateValue(at: 16, statement: statement),
            type: LibraryFileType(databaseValue: optionalInt64Value(at: 17, statement: statement)),
            series: stringValue(at: 18, statement: statement),
            volume: stringValue(at: 19, statement: statement),
            rating: normalizedRating(doubleValue(at: 20, statement: statement)),
            isFavorite: boolValue(at: 21, statement: statement)
        )
    }

    private func normalizedRating(_ rawRating: Double?) -> Double? {
        guard let rawRating, rawRating > 0 else {
            return nil
        }

        return min(max(rawRating, 0), 5)
    }

    private func makeComicMetadata(from statement: OpaquePointer) -> LibraryComicMetadata {
        LibraryComicMetadata(
            comicID: sqlite3_column_int64(statement, 0),
            fileName: stringValue(at: 1, statement: statement) ?? "",
            title: stringValue(at: 2, statement: statement) ?? "",
            series: stringValue(at: 3, statement: statement) ?? "",
            issueNumber: stringValue(at: 4, statement: statement) ?? "",
            volume: stringValue(at: 5, statement: statement) ?? "",
            storyArc: stringValue(at: 6, statement: statement) ?? "",
            publicationDate: stringValue(at: 7, statement: statement) ?? "",
            publisher: stringValue(at: 8, statement: statement) ?? "",
            imprint: stringValue(at: 9, statement: statement) ?? "",
            format: stringValue(at: 10, statement: statement) ?? "",
            languageISO: stringValue(at: 11, statement: statement) ?? "",
            type: LibraryFileType(databaseValue: optionalInt64Value(at: 12, statement: statement)),
            writer: stringValue(at: 13, statement: statement) ?? "",
            penciller: stringValue(at: 14, statement: statement) ?? "",
            inker: stringValue(at: 15, statement: statement) ?? "",
            colorist: stringValue(at: 16, statement: statement) ?? "",
            letterer: stringValue(at: 17, statement: statement) ?? "",
            coverArtist: stringValue(at: 18, statement: statement) ?? "",
            editor: stringValue(at: 19, statement: statement) ?? "",
            synopsis: stringValue(at: 20, statement: statement) ?? "",
            notes: stringValue(at: 21, statement: statement) ?? "",
            review: stringValue(at: 22, statement: statement) ?? "",
            tags: stringValue(at: 23, statement: statement) ?? "",
            characters: stringValue(at: 24, statement: statement) ?? "",
            teams: stringValue(at: 25, statement: statement) ?? "",
            locations: stringValue(at: 26, statement: statement) ?? ""
        )
    }

    private func makeOrganizationCollection(
        from statement: OpaquePointer,
        type: LibraryOrganizationCollectionType
    ) -> LibraryOrganizationCollection {
        let colorName = stringValue(at: 2, statement: statement)
        let ordering = optionalInt64Value(at: 3, statement: statement)

        return LibraryOrganizationCollection(
            id: sqlite3_column_int64(statement, 0),
            name: stringValue(at: 1, statement: statement) ?? "",
            type: type,
            comicCount: intValue(at: 4, statement: statement) ?? 0,
            isAssigned: boolValue(at: 5, statement: statement),
            labelColor: type == .label ? LibraryLabelColor(databaseColorName: colorName, ordering: ordering) : nil
        )
    }

    private func bookmarkPageIndices(statement: OpaquePointer, indices: [Int32]) -> [Int] {
        indices.compactMap { index in
            guard let value = intValue(at: index, statement: statement), value >= 0 else {
                return nil
            }

            return value
        }
    }

    private func sortFolders(lhs: LibraryFolder, rhs: LibraryFolder) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    private func sortComics(lhs: LibraryComic, rhs: LibraryComic) -> Bool {
        switch (lhs.issueLabel, rhs.issueLabel) {
        case let (left?, right?):
            let issueOrder = left.localizedStandardCompare(right)
            if issueOrder != .orderedSame {
                return issueOrder == .orderedAscending
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        let titleOrder = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }

        return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
    }

    private func stringValue(at index: Int32, statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index)
        else {
            return nil
        }

        return String(cString: value)
    }

    private func intValue(at index: Int32, statement: OpaquePointer) -> Int? {
        guard let value = optionalInt64Value(at: index, statement: statement) else {
            return nil
        }

        return Int(value)
    }

    private func optionalInt64Value(at index: Int32, statement: OpaquePointer) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return sqlite3_column_int64(statement, index)
    }

    private func doubleValue(at index: Int32, statement: OpaquePointer) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return sqlite3_column_double(statement, index)
    }

    private func boolValue(at index: Int32, statement: OpaquePointer) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    private func dateValue(at index: Int32, statement: OpaquePointer) -> Date? {
        guard let seconds = optionalInt64Value(at: index, statement: statement), seconds > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func lastDatabaseError(database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }
    #endif
}
