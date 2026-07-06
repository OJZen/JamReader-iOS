import XCTest
@testable import JamReader

final class LibraryScannerDatabaseTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        for harness in harnesses {
            harness.remove()
        }
        harnesses.removeAll()
        super.tearDown()
    }

    func testFullScanIndexesSupportedFilesAndDirectoryComicsAcrossServiceRecreation() throws {
        let harness = try makeHarness()
        try harness.writeFile("Standalone.cbz", bytes: [1, 2, 3])
        try harness.writeFile("Series/Issue 02.pdf", bytes: [4, 5, 6])
        try harness.writeFile("Series/notes.txt", bytes: [7, 8, 9])
        try harness.writeFile("Image Folder/002.png", bytes: [10, 11, 12])
        try harness.writeFile("Image Folder/001.jpg", bytes: [13, 14, 15])

        let databaseURL = try harness.databaseURL
        let summary = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL
        )

        XCTAssertEqual(summary.folderCount, 1)
        XCTAssertEqual(summary.comicCount, 3)
        XCTAssertEqual(summary.previousFolderCount, 0)
        XCTAssertEqual(summary.previousComicCount, 0)
        XCTAssertEqual(summary.reusedComicCount, 0)

        let recreatedReader = LibraryDatabaseReader(fileManager: harness.fileManager)
        let rootContent = try recreatedReader.loadFolderContent(databaseURL: databaseURL)
        XCTAssertEqual(rootContent.subfolders.map(\.displayName), ["Series"])
        XCTAssertEqual(rootContent.comics.map(\.fileName), ["Image Folder", "Standalone.cbz"])

        let allComics = try recreatedReader.loadAllComics(databaseURL: databaseURL)
        XCTAssertEqual(
            allComics.compactMap(\.path).sorted(),
            ["/Image Folder", "/Series/Issue 02.pdf", "/Standalone.cbz"]
        )

        let directoryComic = try XCTUnwrap(allComics.first { $0.fileName == "Image Folder" })
        XCTAssertEqual(directoryComic.pageCount, 2)
        XCTAssertNil(directoryComic.fileSizeBytes)
        XCTAssertEqual(directoryComic.type, .comic)
    }

    func testRescanRemovesMissingComicsAndReportsChangeSummary() throws {
        let harness = try makeHarness()
        try harness.writeFile("Kept.cbz", bytes: [1])
        let removedURL = try harness.writeFile("Removed.pdf", bytes: [2])

        let databaseURL = try harness.databaseURL
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL
        )

        try harness.fileManager.removeItem(at: removedURL)
        let summary = try harness.makeScanner().rescanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL
        )

        XCTAssertEqual(summary.comicCount, 1)
        XCTAssertEqual(summary.previousComicCount, 2)
        XCTAssertEqual(summary.removedComicCount, 1)
        XCTAssertEqual(summary.changeSummaryLine, "Removed 1 comics")

        let allComics = try harness.makeReader().loadAllComics(databaseURL: databaseURL)
        XCTAssertEqual(allComics.map(\.fileName), ["Kept.cbz"])
    }

    func testAppendImportedComicsDoesNotIndexFilesOutsideSourceRoot() throws {
        let harness = try makeHarness()
        let importedURL = try harness.writeFile("Imported/New.cbz", bytes: [1, 2, 3])
        let outsideRootURL = harness.rootURL.appendingPathComponent("Outside/Leak.cbz")
        try harness.fileManager.createDirectory(
            at: outsideRootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([4, 5, 6]).write(to: outsideRootURL)

        let databaseURL = try harness.databaseURL
        let summary = try harness.makeScanner().appendImportedComics(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL,
            fileURLs: [importedURL, outsideRootURL]
        )

        XCTAssertEqual(summary.folderCount, 1)
        XCTAssertEqual(summary.comicCount, 1)

        let allComics = try harness.makeReader().loadAllComics(databaseURL: databaseURL)
        XCTAssertEqual(allComics.map(\.fileName), ["New.cbz"])
        XCTAssertEqual(allComics.compactMap(\.path), ["/Imported/New.cbz"])
    }

    func testSeparateLibrariesDoNotLeakIndexedComics() throws {
        let harness = try makeHarness()
        let secondLibrary = try harness.registerAdditionalLibrary(
            named: "Second Library",
            directoryName: "SecondSourceLibrary"
        )
        try harness.writeFile("First.cbz", bytes: [1])
        try writeFile("Second.cbz", in: secondLibrary.sourceRootURL, using: harness.fileManager, bytes: [2])

        let firstDatabaseURL = try harness.databaseURL
        let scanner = harness.makeScanner()
        let reader = harness.makeReader()
        _ = try scanner.scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: firstDatabaseURL
        )
        _ = try scanner.scanLibrary(
            sourceRootURL: secondLibrary.sourceRootURL,
            databaseURL: secondLibrary.databaseURL
        )

        XCTAssertEqual(
            try reader.loadAllComics(databaseURL: firstDatabaseURL).map(\.fileName),
            ["First.cbz"]
        )
        XCTAssertEqual(
            try reader.loadAllComics(databaseURL: secondLibrary.databaseURL).map(\.fileName),
            ["Second.cbz"]
        )
    }

    func testReadingProgressAndBookmarksPersistAcrossReaderRecreation() throws {
        let harness = try makeHarness()
        try harness.writeFile("Progress.cbz", bytes: [1, 2, 3])

        let databaseURL = try harness.databaseURL
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: databaseURL
        )

        let comic = try XCTUnwrap(harness.makeReader().loadAllComics(databaseURL: databaseURL).first)
        let openedAt = Date(timeIntervalSince1970: 1_234)
        let writer = LibraryDatabaseWriter(fileManager: harness.fileManager)
        try writer.updateReadingProgress(
            for: comic.id,
            progress: ComicReadingProgress(
                currentPage: 7,
                pageCount: 12,
                hasBeenOpened: true,
                read: false,
                lastTimeOpened: openedAt
            ),
            in: databaseURL
        )
        try writer.updateBookmarks(
            for: comic.id,
            bookmarkPageIndices: [9, 2, 5, 20],
            in: databaseURL
        )

        let recreatedReader = LibraryDatabaseReader(fileManager: harness.fileManager)
        let updatedComic = try XCTUnwrap(recreatedReader.loadAllComics(databaseURL: databaseURL).first)
        XCTAssertEqual(updatedComic.currentPage, 7)
        XCTAssertEqual(updatedComic.pageCount, 12)
        XCTAssertTrue(updatedComic.hasBeenOpened)
        XCTAssertFalse(updatedComic.read)
        XCTAssertEqual(updatedComic.lastOpenedAt?.timeIntervalSince1970, openedAt.timeIntervalSince1970)
        XCTAssertEqual(updatedComic.bookmarkPageIndices, [2, 5, 9])
    }

    func testWriterRejectsComicUpdatesAgainstWrongLibraryContext() throws {
        let harness = try makeHarness()
        let secondLibrary = try harness.registerAdditionalLibrary(
            named: "Second Library",
            directoryName: "SecondSourceLibrary"
        )
        try harness.writeFile("First.cbz", bytes: [1])
        try writeFile("Second.cbz", in: secondLibrary.sourceRootURL, using: harness.fileManager, bytes: [2])

        let scanner = harness.makeScanner()
        let firstDatabaseURL = try harness.databaseURL
        _ = try scanner.scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: firstDatabaseURL
        )
        _ = try scanner.scanLibrary(
            sourceRootURL: secondLibrary.sourceRootURL,
            databaseURL: secondLibrary.databaseURL
        )

        let reader = harness.makeReader()
        let firstComic = try XCTUnwrap(reader.loadAllComics(databaseURL: firstDatabaseURL).first)
        let secondComic = try XCTUnwrap(reader.loadAllComics(databaseURL: secondLibrary.databaseURL).first)
        let writer = LibraryDatabaseWriter(fileManager: harness.fileManager)

        XCTAssertThrowsError(
            try writer.setFavorite(true, for: firstComic.id, in: secondLibrary.databaseURL)
        )

        try writer.setFavorite(true, for: secondComic.id, in: secondLibrary.databaseURL)

        XCTAssertFalse(
            try XCTUnwrap(reader.loadAllComics(databaseURL: firstDatabaseURL).first).isFavorite
        )
        XCTAssertTrue(
            try XCTUnwrap(reader.loadAllComics(databaseURL: secondLibrary.databaseURL).first).isFavorite
        )
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func writeFile(
        _ relativePath: String,
        in sourceRootURL: URL,
        using fileManager: FileManager,
        bytes: [UInt8]
    ) throws {
        let url = sourceRootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: url)
    }
}
