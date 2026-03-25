import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

final class SQLiteDatabaseInspector {
    func inspectDatabase(at url: URL) -> LibraryDatabaseSummary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LibraryDatabaseSummary()
        }

        var summary = LibraryDatabaseSummary(exists: true)

        #if canImport(SQLite3)
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let handle else {
            summary.lastError = "Unable to open library.ydb"
            if let handle {
                sqlite3_close(handle)
            }
            return summary
        }

        defer {
            sqlite3_close(handle)
        }

        let hasDBInfoTable = queryTableExists(named: "db_info", database: handle)
        let hasFolderTable = queryTableExists(named: "folder", database: handle)
        let hasComicTable = queryTableExists(named: "comic", database: handle)

        summary.version = queryText("SELECT version FROM db_info LIMIT 1", database: handle)
        summary.folderCount = queryCount("SELECT COUNT(*) FROM folder", database: handle)
        summary.comicCount = queryCount("SELECT COUNT(*) FROM comic", database: handle)

        if !hasDBInfoTable || !hasFolderTable || !hasComicTable {
            summary.lastError = "The database is missing required YACReader tables."
        } else if summary.version == nil {
            summary.lastError = "The database version could not be read from db_info."
        }
        #else
        summary.lastError = "SQLite3 is unavailable in this build."
        #endif

        return summary
    }

    #if canImport(SQLite3)
    private func queryText(_ sql: String, database: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard let text = sqlite3_column_text(statement, 0) else {
            return nil
        }

        return String(cString: text)
    }

    private func queryCount(_ sql: String, database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    private func queryTableExists(named tableName: String, database: OpaquePointer) -> Bool {
        let escapedTableName = tableName.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escapedTableName)' LIMIT 1"
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }

        return sqlite3_step(statement) == SQLITE_ROW
    }
    #endif
}
