import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

enum NativeLibraryStorageError: LocalizedError {
    case sqliteUnavailable
    case invalidLibraryContext
    case openDatabaseFailed(String)
    case statementPreparationFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .invalidLibraryContext:
            return "The library context could not be resolved."
        case .openDatabaseFailed(let reason):
            return "Unable to open the app library database. \(reason)"
        case .statementPreparationFailed(let reason):
            return "Unable to prepare an app library query. \(reason)"
        case .executionFailed(let reason):
            return "Unable to update the app library database. \(reason)"
        }
    }
}

final class AppLibraryDatabase {
    private let fileManager: FileManager
    private let busyTimeoutMilliseconds: Int32 = 5_000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func storageRootURL() throws -> URL {
        let rootURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("JamReader", isDirectory: true)

        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    func fileURL() throws -> URL {
        try storageRootURL().appendingPathComponent("AppLibraryV2.sqlite")
    }

    func contextualDatabaseURL(for libraryID: UUID) throws -> URL {
        let baseURL = try fileURL()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        components.queryItems = [URLQueryItem(name: "libraryID", value: libraryID.uuidString)]
        return components.url ?? baseURL
    }

    func libraryID(from contextualDatabaseURL: URL) -> UUID? {
        guard let components = URLComponents(url: contextualDatabaseURL, resolvingAgainstBaseURL: false),
              let rawValue = components.queryItems?.first(where: { $0.name == "libraryID" })?.value
        else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }

    func ensureInitialized() throws {
        #if canImport(SQLite3)
        _ = try withConnection(readOnly: false) { database in
            sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
            try sqliteExecute("PRAGMA journal_mode = WAL;", database: database)
            try sqliteExecute("PRAGMA synchronous = NORMAL;", database: database)
            try sqliteExecute("PRAGMA foreign_keys = ON;", database: database)
            for statement in schemaStatements {
                try sqliteExecute(statement, database: database)
            }
            try sqliteExecute(
                "INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('schema_version', '2');",
                database: database
            )
        }
        #else
        throw NativeLibraryStorageError.sqliteUnavailable
        #endif
    }

    func withConnection<T>(
        readOnly: Bool,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        #if canImport(SQLite3)
        let databaseFileURL = try fileURL()
        let parentURL = databaseFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        var database: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE

        let openResult = sqlite3_open_v2(databaseFileURL.path, &database, flags, nil)
        guard openResult == SQLITE_OK, let database else {
            let reason = database.map(sqliteLastError) ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw NativeLibraryStorageError.openDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
        try sqliteExecute("PRAGMA foreign_keys = ON;", database: database)
        if !readOnly {
            try sqliteExecute("PRAGMA journal_mode = WAL;", database: database)
            try sqliteExecute("PRAGMA synchronous = NORMAL;", database: database)
        }
        return try body(database)
        #else
        throw NativeLibraryStorageError.sqliteUnavailable
        #endif
    }

    private var schemaStatements: [String] {
        [
            """
            CREATE TABLE IF NOT EXISTS schema_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS libraries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                root_path TEXT NOT NULL,
                bookmark_data BLOB NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS folders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stable_id TEXT NOT NULL UNIQUE,
                library_id TEXT NOT NULL,
                parent_id INTEGER,
                name TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                finished INTEGER NOT NULL DEFAULT 0,
                completed INTEGER NOT NULL DEFAULT 1,
                num_children INTEGER,
                first_child_hash TEXT,
                custom_image TEXT,
                file_type INTEGER NOT NULL DEFAULT 0,
                added_at REAL,
                updated_at REAL,
                FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE,
                FOREIGN KEY(parent_id) REFERENCES folders(id) ON DELETE CASCADE,
                UNIQUE(library_id, relative_path)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS comics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stable_id TEXT NOT NULL UNIQUE,
                library_id TEXT NOT NULL,
                parent_folder_id INTEGER NOT NULL,
                file_name TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                file_hash TEXT NOT NULL,
                title TEXT,
                issue_number TEXT,
                current_page INTEGER NOT NULL DEFAULT 1,
                page_count INTEGER,
                bookmark1 INTEGER NOT NULL DEFAULT -1,
                bookmark2 INTEGER NOT NULL DEFAULT -1,
                bookmark3 INTEGER NOT NULL DEFAULT -1,
                is_read INTEGER NOT NULL DEFAULT 0,
                has_been_opened INTEGER NOT NULL DEFAULT 0,
                cover_size_ratio REAL,
                last_opened_at REAL,
                added_at REAL,
                file_type INTEGER NOT NULL DEFAULT 0,
                series TEXT,
                volume TEXT,
                rating REAL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                story_arc TEXT,
                publication_date TEXT,
                publisher TEXT,
                imprint TEXT,
                format TEXT,
                language_iso TEXT,
                writer TEXT,
                penciller TEXT,
                inker TEXT,
                colorist TEXT,
                letterer TEXT,
                cover_artist TEXT,
                editor TEXT,
                synopsis TEXT,
                notes TEXT,
                review TEXT,
                tags_text TEXT,
                characters TEXT,
                teams TEXT,
                locations TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE,
                FOREIGN KEY(parent_folder_id) REFERENCES folders(id) ON DELETE CASCADE,
                UNIQUE(library_id, relative_path)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stable_id TEXT NOT NULL UNIQUE,
                library_id TEXT NOT NULL,
                name TEXT NOT NULL,
                color_name TEXT NOT NULL,
                color_ordering INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS comic_tags (
                tag_id INTEGER NOT NULL,
                comic_id INTEGER NOT NULL,
                ordering_index INTEGER NOT NULL,
                PRIMARY KEY(tag_id, comic_id),
                FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE,
                FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS reading_lists (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                stable_id TEXT NOT NULL UNIQUE,
                library_id TEXT NOT NULL,
                name TEXT NOT NULL,
                ordering_index INTEGER NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS reading_list_items (
                reading_list_id INTEGER NOT NULL,
                comic_id INTEGER NOT NULL,
                ordering_index INTEGER NOT NULL,
                PRIMARY KEY(reading_list_id, comic_id),
                FOREIGN KEY(reading_list_id) REFERENCES reading_lists(id) ON DELETE CASCADE,
                FOREIGN KEY(comic_id) REFERENCES comics(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS scan_runs (
                library_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                summary_json BLOB NOT NULL,
                scope TEXT NOT NULL,
                context_path TEXT,
                scanned_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(library_id) REFERENCES libraries(id) ON DELETE CASCADE
            );
            """,
            "CREATE INDEX IF NOT EXISTS folders_library_parent_idx ON folders (library_id, parent_id);",
            "CREATE INDEX IF NOT EXISTS folders_library_path_idx ON folders (library_id, relative_path);",
            "CREATE INDEX IF NOT EXISTS comics_library_parent_idx ON comics (library_id, parent_folder_id);",
            "CREATE INDEX IF NOT EXISTS comics_library_path_idx ON comics (library_id, relative_path);",
            "CREATE INDEX IF NOT EXISTS comics_library_hash_idx ON comics (library_id, file_hash);",
            "CREATE INDEX IF NOT EXISTS comics_library_title_idx ON comics (library_id, title);",
            "CREATE INDEX IF NOT EXISTS tags_library_idx ON tags (library_id, name);",
            "CREATE INDEX IF NOT EXISTS reading_lists_library_idx ON reading_lists (library_id, ordering_index);",
        ]
    }
}

final class LibraryAssetStore {
    private let database: AppLibraryDatabase
    private let fileManager: FileManager

    init(
        database: AppLibraryDatabase,
        fileManager: FileManager = .default
    ) {
        self.database = database
        self.fileManager = fileManager
    }

    func rootURL(for libraryID: UUID) throws -> URL {
        try database
            .storageRootURL()
            .appendingPathComponent("LibraryAssets", isDirectory: true)
            .appendingPathComponent(libraryID.uuidString, isDirectory: true)
    }

    func coversRootURL(for libraryID: UUID) throws -> URL {
        try rootURL(for: libraryID).appendingPathComponent("covers", isDirectory: true)
    }

    func folderCoversRootURL(for libraryID: UUID) throws -> URL {
        try coversRootURL(for: libraryID).appendingPathComponent("folders", isDirectory: true)
    }

    func plannedCoverURL(hash: String, libraryID: UUID) throws -> URL {
        try coversRootURL(for: libraryID).appendingPathComponent("\(hash).jpg")
    }

    func plannedCoverURL(assetKey: String, libraryID: UUID) throws -> URL {
        try coversRootURL(for: libraryID).appendingPathComponent("\(assetKey).jpg")
    }

    func plannedFolderCoverURL(folderID: Int64, libraryID: UUID) throws -> URL {
        try folderCoversRootURL(for: libraryID).appendingPathComponent("\(folderID).jpg")
    }

    func ensureLibraryDirectories(for libraryID: UUID) throws {
        let rootURL = try rootURL(for: libraryID)
        let coversURL = try coversRootURL(for: libraryID)
        let foldersURL = try folderCoversRootURL(for: libraryID)

        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: coversURL.path) {
            try fileManager.createDirectory(at: coversURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: foldersURL.path) {
            try fileManager.createDirectory(at: foldersURL, withIntermediateDirectories: true)
        }
    }

    func deleteAssets(for libraryID: UUID) {
        guard let rootURL = try? rootURL(for: libraryID),
              fileManager.fileExists(atPath: rootURL.path)
        else {
            return
        }

        try? fileManager.removeItem(at: rootURL)
    }

    func deleteCover(hash: String, libraryID: UUID) {
        guard let coverURL = try? plannedCoverURL(hash: hash, libraryID: libraryID),
              fileManager.fileExists(atPath: coverURL.path)
        else {
            return
        }

        try? fileManager.removeItem(at: coverURL)
    }

    func deleteCover(assetKey: String, libraryID: UUID) {
        guard let coverURL = try? plannedCoverURL(assetKey: assetKey, libraryID: libraryID),
              fileManager.fileExists(atPath: coverURL.path)
        else {
            return
        }

        try? fileManager.removeItem(at: coverURL)
    }

    func deleteFolderCover(folderID: Int64, libraryID: UUID) {
        guard let coverURL = try? plannedFolderCoverURL(folderID: folderID, libraryID: libraryID),
              fileManager.fileExists(atPath: coverURL.path)
        else {
            return
        }

        try? fileManager.removeItem(at: coverURL)
    }
}

final class LibraryCatalogRepository {
    private let database: AppLibraryDatabase
    private let assetStore: LibraryAssetStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        database: AppLibraryDatabase,
        assetStore: LibraryAssetStore
    ) {
        self.database = database
        self.assetStore = assetStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func loadLibraries() throws -> [LibraryDescriptor] {
        try database.ensureInitialized()

        return try database.withConnection(readOnly: true) { database in
            let sql = """
            SELECT id, kind, name, root_path, bookmark_data, created_at, updated_at
            FROM libraries
            ORDER BY name COLLATE NOCASE, created_at ASC
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            var libraries: [LibraryDescriptor] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let rawIdentifier = sqliteString(statement, index: 0),
                      let identifier = UUID(uuidString: rawIdentifier),
                      let rawKind = sqliteString(statement, index: 1),
                      let kind = LibraryKind(rawValue: rawKind)
                else {
                    continue
                }

                libraries.append(
                    LibraryDescriptor(
                        id: identifier,
                        kind: kind,
                        name: sqliteString(statement, index: 2) ?? "Untitled Library",
                        rootPath: sqliteString(statement, index: 3) ?? "",
                        bookmarkData: sqliteData(statement, index: 4) ?? Data(),
                        createdAt: sqliteDate(statement, index: 5) ?? Date.distantPast,
                        updatedAt: sqliteDate(statement, index: 6) ?? Date.distantPast
                    )
                )
            }

            return libraries
        }
    }

    func replaceLibraries(with descriptors: [LibraryDescriptor]) throws {
        try database.ensureInitialized()
        let descriptorIDs = Set(descriptors.map(\.id.uuidString))
        let removedIDs = try existingLibraryIDs().subtracting(descriptorIDs)

        try database.withConnection(readOnly: false) { database in
            try sqliteBeginTransaction(database: database)
            do {
                let upsertSQL = """
                INSERT INTO libraries (id, kind, name, root_path, bookmark_data, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    name = excluded.name,
                    root_path = excluded.root_path,
                    bookmark_data = excluded.bookmark_data,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at
                """

                let statement = try sqlitePrepare(upsertSQL, database: database)
                defer { sqlite3_finalize(statement) }

                for descriptor in descriptors {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqliteBindText(descriptor.id.uuidString, index: 1, statement: statement)
                    sqliteBindText(descriptor.kind.rawValue, index: 2, statement: statement)
                    sqliteBindText(descriptor.name, index: 3, statement: statement)
                    sqliteBindText(descriptor.rootPath, index: 4, statement: statement)
                    sqliteBindData(descriptor.bookmarkData, index: 5, statement: statement)
                    sqliteBindDate(descriptor.createdAt, index: 6, statement: statement)
                    sqliteBindDate(descriptor.updatedAt, index: 7, statement: statement)
                    try sqliteStepDone(statement, database: database)
                    try assetStore.ensureLibraryDirectories(for: descriptor.id)
                }

                if !removedIDs.isEmpty {
                    let deleteSQL = "DELETE FROM libraries WHERE id = ?"
                    let deleteStatement = try sqlitePrepare(deleteSQL, database: database)
                    defer { sqlite3_finalize(deleteStatement) }

                    for removedID in removedIDs {
                        sqlite3_reset(deleteStatement)
                        sqlite3_clear_bindings(deleteStatement)
                        sqliteBindText(removedID, index: 1, statement: deleteStatement)
                        try sqliteStepDone(deleteStatement, database: database)
                    }
                }

                try sqliteCommitTransaction(database: database)
            } catch {
                sqliteRollbackTransaction(database: database)
                throw error
            }
        }

        removedIDs.compactMap(UUID.init(uuidString:)).forEach { assetStore.deleteAssets(for: $0) }
    }

    func loadMaintenanceRecord(for libraryID: UUID) throws -> LibraryMaintenanceRecord? {
        try database.ensureInitialized()

        return try database.withConnection(readOnly: true) { database in
            let sql = """
            SELECT title, summary_json, scope, context_path, scanned_at
            FROM scan_runs
            WHERE library_id = ?
            LIMIT 1
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let title = sqliteString(statement, index: 0),
                  let summaryData = sqliteData(statement, index: 1),
                  let rawScope = sqliteString(statement, index: 2),
                  let scope = LibraryMaintenanceRecord.Scope(rawValue: rawScope),
                  let summary = try? decoder.decode(LibraryScanSummary.self, from: summaryData)
            else {
                return nil
            }

            return LibraryMaintenanceRecord(
                libraryID: libraryID,
                title: title,
                summary: summary,
                scope: scope,
                contextPath: sqliteString(statement, index: 3),
                scannedAt: sqliteDate(statement, index: 4) ?? Date()
            )
        }
    }

    func saveMaintenanceRecord(_ record: LibraryMaintenanceRecord) throws {
        try database.ensureInitialized()
        let summaryData = try encoder.encode(record.summary)

        try database.withConnection(readOnly: false) { database in
            let sql = """
            INSERT INTO scan_runs (library_id, title, summary_json, scope, context_path, scanned_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(library_id) DO UPDATE SET
                title = excluded.title,
                summary_json = excluded.summary_json,
                scope = excluded.scope,
                context_path = excluded.context_path,
                scanned_at = excluded.scanned_at,
                updated_at = excluded.updated_at
            """

            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            sqliteBindText(record.libraryID.uuidString, index: 1, statement: statement)
            sqliteBindText(record.title, index: 2, statement: statement)
            sqliteBindData(summaryData, index: 3, statement: statement)
            sqliteBindText(record.scope.rawValue, index: 4, statement: statement)
            sqliteBindOptionalText(record.contextPath, index: 5, statement: statement)
            sqliteBindDate(record.scannedAt, index: 6, statement: statement)
            sqliteBindDate(Date(), index: 7, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    func clearMaintenanceRecord(for libraryID: UUID) throws {
        try database.ensureInitialized()

        try database.withConnection(readOnly: false) { database in
            let sql = "DELETE FROM scan_runs WHERE library_id = ?"
            let statement = try sqlitePrepare(sql, database: database)
            defer { sqlite3_finalize(statement) }
            sqliteBindText(libraryID.uuidString, index: 1, statement: statement)
            try sqliteStepDone(statement, database: database)
        }
    }

    private func existingLibraryIDs() throws -> Set<String> {
        try database.ensureInitialized()

        return try database.withConnection(readOnly: true) { database in
            let statement = try sqlitePrepare("SELECT id FROM libraries", database: database)
            defer { sqlite3_finalize(statement) }

            var ids = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                if let identifier = sqliteString(statement, index: 0) {
                    ids.insert(identifier)
                }
            }

            return ids
        }
    }
}

#if canImport(SQLite3)
let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@discardableResult
func sqliteExecute(_ sql: String, database: OpaquePointer) throws -> Int32 {
    let result = sqlite3_exec(database, sql, nil, nil, nil)
    guard result == SQLITE_OK else {
        throw NativeLibraryStorageError.executionFailed(sqliteLastError(database))
    }

    return result
}

func sqlitePrepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement
    else {
        throw NativeLibraryStorageError.statementPreparationFailed(sqliteLastError(database))
    }

    return statement
}

func sqliteStepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw NativeLibraryStorageError.executionFailed(sqliteLastError(database))
    }
}

func sqliteBeginTransaction(database: OpaquePointer) throws {
    try sqliteExecute("BEGIN IMMEDIATE TRANSACTION", database: database)
}

func sqliteCommitTransaction(database: OpaquePointer) throws {
    try sqliteExecute("COMMIT", database: database)
}

func sqliteRollbackTransaction(database: OpaquePointer) {
    sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
}

func sqliteLastError(_ database: OpaquePointer) -> String {
    guard let message = sqlite3_errmsg(database) else {
        return "Unknown SQLite error."
    }

    return String(cString: message)
}

func sqliteBindText(_ text: String, index: Int32, statement: OpaquePointer) {
    sqlite3_bind_text(statement, index, text, -1, sqliteTransientDestructor)
}

func sqliteBindOptionalText(_ text: String?, index: Int32, statement: OpaquePointer) {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        sqlite3_bind_null(statement, index)
        return
    }

    sqliteBindText(text, index: index, statement: statement)
}

func sqliteBindData(_ data: Data, index: Int32, statement: OpaquePointer) {
    data.withUnsafeBytes { rawBuffer in
        let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
        sqlite3_bind_blob(statement, index, baseAddress, Int32(data.count), sqliteTransientDestructor)
    }
}

func sqliteBindDate(_ date: Date, index: Int32, statement: OpaquePointer) {
    sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
}

func sqliteString(_ statement: OpaquePointer, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else {
        return nil
    }

    return String(cString: value)
}

func sqliteData(_ statement: OpaquePointer, index: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(statement, index) else {
        return nil
    }

    let count = Int(sqlite3_column_bytes(statement, index))
    return Data(bytes: bytes, count: count)
}

func sqliteDate(_ statement: OpaquePointer, index: Int32) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
        return nil
    }

    return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
}
#endif
