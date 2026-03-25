import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

enum LibraryDatabaseBootstrapError: LocalizedError {
    case sqliteUnavailable
    case databaseAlreadyExists
    case createDatabaseFailed(String)
    case schemaCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqliteUnavailable:
            return "SQLite3 is unavailable in this build."
        case .databaseAlreadyExists:
            return "This library already has a library.ydb database."
        case .createDatabaseFailed(let reason):
            return "Unable to create library database. \(reason)"
        case .schemaCreationFailed(let reason):
            return "Unable to initialize the library schema. \(reason)"
        }
    }
}

final class LibraryDatabaseBootstrapper {
    static let currentDatabaseVersion = "9.16.0"
    static let supportedDatabaseMajorVersion = currentDatabaseVersion.split(separator: ".").first.map(String.init) ?? currentDatabaseVersion

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureDatabaseExists(at databaseURL: URL) throws {
        if fileManager.fileExists(atPath: databaseURL.path) {
            return
        }

        try createDatabaseIfNeeded(at: databaseURL)
    }

    static func supportsDatabaseVersion(_ version: String?) -> Bool {
        guard let version,
              let versionMajor = version.split(separator: ".").first.map(String.init) else {
            return false
        }

        return versionMajor == supportedDatabaseMajorVersion
    }

    func createDatabaseIfNeeded(at databaseURL: URL) throws {
        guard !fileManager.fileExists(atPath: databaseURL.path) else {
            throw LibraryDatabaseBootstrapError.databaseAlreadyExists
        }

        let parentURL = databaseURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            let reason = database.map { lastDatabaseError(database: $0) } ?? "Unknown SQLite error."
            if let database {
                sqlite3_close(database)
            }
            throw LibraryDatabaseBootstrapError.createDatabaseFailed(reason)
        }

        defer {
            sqlite3_close(database)
        }

        try execute("PRAGMA foreign_keys = ON;", database: database)
        try execute("BEGIN TRANSACTION;", database: database)

        do {
            try createTables(database: database)
            try execute("COMMIT;", database: database)
        } catch {
            _ = try? execute("ROLLBACK;", database: database)
            throw error
        }
        #else
        throw LibraryDatabaseBootstrapError.sqliteUnavailable
        #endif
    }

    #if canImport(SQLite3)
    private func createTables(database: OpaquePointer) throws {
        let statements = [
            createComicInfoTableSQL,
            createFolderTableSQL,
            createComicTableSQL,
            createDBInfoTableSQL,
            "INSERT INTO db_info (version) VALUES ('\(Self.currentDatabaseVersion)');",
            createLabelTableSQL,
            "CREATE INDEX label_ordering_index ON label (ordering);",
            createComicLabelTableSQL,
            "CREATE INDEX comic_label_ordering_index ON comic_label (ordering);",
            createReadingListTableSQL,
            "CREATE INDEX reading_list_ordering_index ON reading_list (ordering);",
            createComicReadingListTableSQL,
            "CREATE INDEX comic_reading_list_ordering_index ON comic_reading_list (ordering);",
            createDefaultReadingListTableSQL,
            createComicDefaultReadingListTableSQL,
            "CREATE INDEX comic_default_reading_list_ordering_index ON comic_default_reading_list (ordering);",
            "INSERT INTO default_reading_list (name) VALUES ('Favorites');",
            "INSERT INTO folder (parentId, name, path, added) VALUES (1, 'root', '/', strftime('%s','now'));"
        ]

        for statement in statements {
            try execute(statement, database: database)
        }
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw LibraryDatabaseBootstrapError.schemaCreationFailed(lastDatabaseError(database: database))
        }
    }

    private func lastDatabaseError(database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: message)
    }

    private var createComicInfoTableSQL: String {
        """
        CREATE TABLE comic_info (
            id INTEGER PRIMARY KEY,
            title TEXT,
            coverPage INTEGER DEFAULT 1,
            numPages INTEGER,
            number TEXT,
            isBis BOOLEAN,
            count INTEGER,
            volume TEXT,
            storyArc TEXT,
            arcNumber TEXT,
            arcCount INTEGER,
            genere TEXT,
            writer TEXT,
            penciller TEXT,
            inker TEXT,
            colorist TEXT,
            letterer TEXT,
            coverArtist TEXT,
            date TEXT,
            publisher TEXT,
            format TEXT,
            color BOOLEAN,
            ageRating TEXT,
            synopsis TEXT,
            characters TEXT,
            notes TEXT,
            hash TEXT UNIQUE NOT NULL,
            edited BOOLEAN DEFAULT 0,
            read BOOLEAN DEFAULT 0,
            hasBeenOpened BOOLEAN DEFAULT 0,
            rating REAL DEFAULT 0,
            currentPage INTEGER DEFAULT 1,
            bookmark1 INTEGER DEFAULT -1,
            bookmark2 INTEGER DEFAULT -1,
            bookmark3 INTEGER DEFAULT -1,
            brightness INTEGER DEFAULT -1,
            contrast INTEGER DEFAULT -1,
            gamma INTEGER DEFAULT -1,
            comicVineID TEXT,
            lastTimeOpened INTEGER,
            coverSizeRatio REAL,
            originalCoverSize STRING,
            manga BOOLEAN DEFAULT 0,
            added INTEGER,
            type INTEGER DEFAULT 0,
            editor TEXT,
            imprint TEXT,
            teams TEXT,
            locations TEXT,
            series TEXT,
            alternateSeries TEXT,
            alternateNumber TEXT,
            alternateCount INTEGER,
            languageISO TEXT,
            seriesGroup TEXT,
            mainCharacterOrTeam TEXT,
            review TEXT,
            tags TEXT,
            imageFiltersJson TEXT,
            lastTimeImageFiltersSet INTEGER DEFAULT 0,
            lastTimeCoverSet INTEGER DEFAULT 0,
            usesExternalCover BOOLEAN DEFAULT 0,
            lastTimeMetadataSet INTEGER DEFAULT 0
        );
        """
    }

    private var createFolderTableSQL: String {
        """
        CREATE TABLE folder (
            id INTEGER PRIMARY KEY,
            parentId INTEGER NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            finished BOOLEAN DEFAULT 0,
            completed BOOLEAN DEFAULT 1,
            numChildren INTEGER,
            firstChildHash TEXT,
            customImage TEXT,
            manga BOOLEAN DEFAULT 0,
            type INTEGER DEFAULT 0,
            added INTEGER,
            updated INTEGER,
            FOREIGN KEY(parentId) REFERENCES folder(id) ON DELETE CASCADE
        );
        """
    }

    private var createComicTableSQL: String {
        """
        CREATE TABLE comic (
            id INTEGER PRIMARY KEY,
            parentId INTEGER NOT NULL,
            comicInfoId INTEGER NOT NULL,
            fileName TEXT NOT NULL,
            path TEXT,
            FOREIGN KEY(parentId) REFERENCES folder(id) ON DELETE CASCADE,
            FOREIGN KEY(comicInfoId) REFERENCES comic_info(id)
        );
        """
    }

    private var createDBInfoTableSQL: String {
        "CREATE TABLE db_info (version TEXT NOT NULL);"
    }

    private var createLabelTableSQL: String {
        """
        CREATE TABLE label (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            ordering INTEGER NOT NULL
        );
        """
    }

    private var createComicLabelTableSQL: String {
        """
        CREATE TABLE comic_label (
            comic_id INTEGER,
            label_id INTEGER,
            ordering INTEGER,
            FOREIGN KEY(label_id) REFERENCES label(id) ON DELETE CASCADE,
            FOREIGN KEY(comic_id) REFERENCES comic(id) ON DELETE CASCADE,
            PRIMARY KEY(label_id, comic_id)
        );
        """
    }

    private var createReadingListTableSQL: String {
        """
        CREATE TABLE reading_list (
            id INTEGER PRIMARY KEY,
            parentId INTEGER,
            ordering INTEGER DEFAULT 0,
            name TEXT NOT NULL,
            finished BOOLEAN DEFAULT 0,
            completed BOOLEAN DEFAULT 1,
            manga BOOLEAN DEFAULT 0,
            FOREIGN KEY(parentId) REFERENCES reading_list(id) ON DELETE CASCADE
        );
        """
    }

    private var createComicReadingListTableSQL: String {
        """
        CREATE TABLE comic_reading_list (
            reading_list_id INTEGER,
            comic_id INTEGER,
            ordering INTEGER,
            FOREIGN KEY(reading_list_id) REFERENCES reading_list(id) ON DELETE CASCADE,
            FOREIGN KEY(comic_id) REFERENCES comic(id) ON DELETE CASCADE,
            PRIMARY KEY(reading_list_id, comic_id)
        );
        """
    }

    private var createDefaultReadingListTableSQL: String {
        """
        CREATE TABLE default_reading_list (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
        );
        """
    }

    private var createComicDefaultReadingListTableSQL: String {
        """
        CREATE TABLE comic_default_reading_list (
            comic_id INTEGER,
            default_reading_list_id INTEGER,
            ordering INTEGER,
            FOREIGN KEY(default_reading_list_id) REFERENCES default_reading_list(id) ON DELETE CASCADE,
            FOREIGN KEY(comic_id) REFERENCES comic(id) ON DELETE CASCADE,
            PRIMARY KEY(default_reading_list_id, comic_id)
        );
        """
    }
    #endif
}
