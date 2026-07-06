import XCTest
@testable import JamReader

final class ImportedComicsImportResultTests: XCTestCase {
    func testCompletionMessageReportsCreatedLibraryAndImportedComicCount() {
        let result = makeResult(
            createdLibrary: true,
            importedComicCount: 1
        )

        XCTAssertEqual(
            result.completionMessageLines(),
            [
                "Added Imported Comics.",
                "Imported 1 comic file into Imported Comics."
            ]
        )
        XCTAssertTrue(result.hasImportedAnyComics)
    }

    func testCompletionMessageReportsScanErrorRecoveryGuidance() {
        let result = makeResult(
            importedComicCount: 2,
            scanErrorMessage: "database is locked"
        )

        XCTAssertEqual(
            result.completionMessageLines(),
            [
                "Imported 2 comic files into Imported Comics.",
                "Automatic indexing failed: database is locked",
                "Open Imported Comics and run Refresh to index the new files."
            ]
        )
    }

    func testCompletionMessageReportsUnsupportedAndFailedItems() {
        let result = makeResult(
            unsupportedItemNames: ["notes.txt", "metadata.json"],
            failedItemNames: ["z.cbz", "a.cbz", "a.cbz"]
        )

        XCTAssertEqual(
            result.completionMessageLines(extraFailedItemNames: ["c.cbz", "b.cbz"]),
            [
                "Skipped 2 unsupported items.",
                "Failed to import 5 item(s): a.cbz, b.cbz, c.cbz, +1 more."
            ]
        )
    }

    private func makeResult(
        createdLibrary: Bool = false,
        importedComicCount: Int = 0,
        scanErrorMessage: String? = nil,
        unsupportedItemNames: [String] = [],
        failedItemNames: [String] = []
    ) -> ImportedComicsImportResult {
        ImportedComicsImportResult(
            importedDestinationID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            importedDestinationName: "Imported Comics",
            createdLibrary: createdLibrary,
            importedComicCount: importedComicCount,
            scanSummary: nil,
            scanErrorMessage: scanErrorMessage,
            unsupportedItemNames: unsupportedItemNames,
            failedItemNames: failedItemNames
        )
    }
}
