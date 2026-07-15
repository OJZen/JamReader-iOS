import XCTest
@testable import JamReader

final class LibraryComicDeletionTransactionTests: XCTestCase {
    private var harness: LibraryDatabaseTestHarness?

    override func tearDown() {
        harness?.remove()
        harness = nil
        super.tearDown()
    }

    func testBatchDeleteRollsBackEarlierDeletionWhenLaterDeletionFails() throws {
        let harness = try LibraryDatabaseTestHarness.make()
        self.harness = harness
        try harness.writeFile("First.cbz", bytes: [1])
        try harness.writeFile("Second.cbz", bytes: [2])
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: harness.databaseURL
        )
        let comics = try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL)
        XCTAssertEqual(comics.count, 2)

        let libraryID = harness.descriptor.id.uuidString
        _ = try harness.database.withConnection(readOnly: false) { database in
            try sqliteExecute(
                """
                CREATE TRIGGER fail_when_deleting_last_test_comic
                BEFORE DELETE ON comics
                WHEN OLD.library_id = '\(libraryID)'
                  AND (SELECT COUNT(*) FROM comics WHERE library_id = OLD.library_id) = 1
                BEGIN
                    SELECT RAISE(ABORT, 'Injected batch delete failure');
                END;
                """,
                database: database
            )
        }

        XCTAssertThrowsError(
            try LibraryDatabaseWriter(fileManager: harness.fileManager).deleteComics(
                comics.map(\.id),
                in: harness.databaseURL
            )
        )

        let remainingIDs = Set(
            try harness.makeReader()
                .loadAllComics(databaseURL: harness.databaseURL)
                .map(\.id)
        )
        XCTAssertEqual(remainingIDs, Set(comics.map(\.id)))
    }
}
