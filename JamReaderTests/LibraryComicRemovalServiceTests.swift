import XCTest
@testable import JamReader

final class LibraryComicRemovalServiceTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        for harness in harnesses {
            harness.remove()
        }
        harnesses.removeAll()
        super.tearDown()
    }

    func testSuccessfulRemovalCommitsDatabaseBeforeCleaningQuarantineAndCover() throws {
        let harness = try makeHarness()
        let firstURL = try harness.writeFile("First.cbz", bytes: [1])
        let secondURL = try harness.writeFile("Folder/Second.cbz", bytes: [2])
        let comics = try scanAndLoadComics(harness)
        let storageManager = makeStorageManager(harness)
        let coverLocator = LibraryCoverLocator(fileManager: harness.fileManager)
        let coverURL = coverLocator.plannedCoverURL(
            for: try XCTUnwrap(comics.first),
            metadataRootURL: storageManager.metadataRootURL(for: harness.descriptor)
        )
        try harness.fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([3]).write(to: coverURL)
        let databaseWriter = RecordingComicDatabaseDeleter()
        databaseWriter.onDelete = { comicIDs, databaseURL in
            XCTAssertFalse(harness.fileManager.fileExists(atPath: firstURL.path))
            XCTAssertFalse(harness.fileManager.fileExists(atPath: secondURL.path))
            XCTAssertEqual(try self.quarantineDirectoryNames(in: harness).count, 1)
            try LibraryDatabaseWriter(fileManager: harness.fileManager)
                .deleteComics(comicIDs, in: databaseURL)
        }

        let service = LibraryComicRemovalService(
            storageManager: storageManager,
            databaseWriter: databaseWriter,
            coverLocator: coverLocator,
            fileManager: harness.fileManager
        )

        try service.removeComics(comics, from: harness.descriptor)

        XCTAssertFalse(harness.fileManager.fileExists(atPath: firstURL.path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: secondURL.path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: coverURL.path))
        XCTAssertEqual(try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL), [])
        XCTAssertEqual(databaseWriter.deletedComicIDs, [comics.map(\.id)])
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testSecondMoveFailureRollsBackFirstMoveAndSkipsDatabaseDelete() throws {
        let harness = try makeHarness()
        let firstURL = try harness.writeFile("First.cbz", bytes: [1])
        let secondURL = try harness.writeFile("Second.cbz", bytes: [2])
        let comics = try scanAndLoadComics(harness)
        let fileManager = FailureInjectingRemovalFileManager(
            base: harness.fileManager,
            failingMoveNumber: 2
        )
        let databaseWriter = RecordingComicDatabaseDeleter()
        let service = makeService(
            harness: harness,
            databaseWriter: databaseWriter,
            fileManager: fileManager
        )

        XCTAssertThrowsError(
            try service.removeComics(comics, from: harness.descriptor)
        ) { error in
            guard case TestFailure.move(2) = error else {
                return XCTFail("Expected the injected second-move failure, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: firstURL), Data([1]))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data([2]))
        XCTAssertEqual(databaseWriter.deleteCallCount, 0)
        XCTAssertEqual(fileManager.moveCallCount, 3)
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testDatabaseDeleteFailureRestoresEveryQuarantinedComic() throws {
        let harness = try makeHarness()
        let firstURL = try harness.writeFile("First.cbz", bytes: [1])
        let secondURL = try harness.writeFile("Second.cbz", bytes: [2])
        let comics = try scanAndLoadComics(harness)
        let databaseWriter = RecordingComicDatabaseDeleter(error: TestFailure.database)
        databaseWriter.onDelete = { _, _ in
            XCTAssertFalse(harness.fileManager.fileExists(atPath: firstURL.path))
            XCTAssertFalse(harness.fileManager.fileExists(atPath: secondURL.path))
            XCTAssertEqual(try self.quarantineDirectoryNames(in: harness).count, 1)
        }
        let service = makeService(
            harness: harness,
            databaseWriter: databaseWriter,
            fileManager: harness.fileManager
        )

        XCTAssertThrowsError(
            try service.removeComics(comics, from: harness.descriptor)
        ) { error in
            guard case TestFailure.database = error else {
                return XCTFail("Expected the injected database failure, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: firstURL), Data([1]))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data([2]))
        XCTAssertEqual(databaseWriter.deletedComicIDs, [comics.map(\.id)])
        XCTAssertEqual(databaseWriter.deleteCallCount, 1)
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testDanglingSymlinkIsRemovedInsteadOfBeingSkipped() throws {
        let harness = try makeHarness()
        let comicURL = try harness.writeFile("Comic.cbz", bytes: [1])
        let comic = try XCTUnwrap(scanAndLoadComics(harness).first)
        try harness.fileManager.removeItem(at: comicURL)
        try harness.fileManager.createSymbolicLink(
            atPath: comicURL.path,
            withDestinationPath: "Missing.cbz"
        )
        XCTAssertFalse(harness.fileManager.fileExists(atPath: comicURL.path))
        XCTAssertEqual(
            try harness.fileManager.destinationOfSymbolicLink(atPath: comicURL.path),
            "Missing.cbz"
        )

        try makeService(
            harness: harness,
            databaseWriter: LibraryDatabaseWriter(fileManager: harness.fileManager),
            fileManager: harness.fileManager
        ).removeComic(comic, from: harness.descriptor)

        XCTAssertThrowsError(
            try harness.fileManager.destinationOfSymbolicLink(atPath: comicURL.path)
        )
        XCTAssertEqual(try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL), [])
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testDatabaseFailureRestoresDanglingSymlinkFromQuarantine() throws {
        let harness = try makeHarness()
        let comicURL = try harness.writeFile("Comic.cbz", bytes: [1])
        let comic = try XCTUnwrap(scanAndLoadComics(harness).first)
        try harness.fileManager.removeItem(at: comicURL)
        try harness.fileManager.createSymbolicLink(
            atPath: comicURL.path,
            withDestinationPath: "Missing.cbz"
        )
        let databaseWriter = RecordingComicDatabaseDeleter(error: TestFailure.database)

        XCTAssertThrowsError(
            try makeService(
                harness: harness,
                databaseWriter: databaseWriter,
                fileManager: harness.fileManager
            ).removeComic(comic, from: harness.descriptor)
        )

        XCTAssertEqual(
            try harness.fileManager.destinationOfSymbolicLink(atPath: comicURL.path),
            "Missing.cbz"
        )
        XCTAssertEqual(databaseWriter.deleteCallCount, 1)
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testCoverCleanupFailureDoesNotUndoCommittedComicRemoval() throws {
        let harness = try makeHarness()
        let comicURL = try harness.writeFile("Comic.cbz", bytes: [1])
        let comic = try XCTUnwrap(scanAndLoadComics(harness).first)
        let storageManager = makeStorageManager(harness)
        let coverLocator = LibraryCoverLocator(fileManager: harness.fileManager)
        let coverURL = coverLocator.plannedCoverURL(
            for: comic,
            metadataRootURL: storageManager.metadataRootURL(for: harness.descriptor)
        )
        try harness.fileManager.createDirectory(
            at: coverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([2]).write(to: coverURL)
        let fileManager = FailureInjectingRemovalFileManager(
            base: harness.fileManager,
            failingRemovalURL: coverURL
        )
        let service = LibraryComicRemovalService(
            storageManager: storageManager,
            databaseWriter: LibraryDatabaseWriter(fileManager: harness.fileManager),
            coverLocator: coverLocator,
            fileManager: fileManager
        )

        XCTAssertNoThrow(try service.removeComic(comic, from: harness.descriptor))

        XCTAssertFalse(harness.fileManager.fileExists(atPath: comicURL.path))
        XCTAssertTrue(harness.fileManager.fileExists(atPath: coverURL.path))
        XCTAssertEqual(try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL), [])
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testPathEscapingSourceRootIsRejectedBeforeAnyMoveOrDatabaseDelete() throws {
        let harness = try makeHarness()
        let safeURL = try harness.writeFile("Safe.cbz", bytes: [8])
        let safeComic = try XCTUnwrap(scanAndLoadComics(harness).first)
        let outsideURL = harness.rootURL.appendingPathComponent("Outside.cbz")
        try Data([9]).write(to: outsideURL)
        let fileManager = FailureInjectingRemovalFileManager(base: harness.fileManager)
        let databaseWriter = RecordingComicDatabaseDeleter()
        let service = makeService(
            harness: harness,
            databaseWriter: databaseWriter,
            fileManager: fileManager
        )

        XCTAssertThrowsError(
            try service.removeComics(
                [
                    safeComic,
                    makeComic(id: 99, fileName: "Outside.cbz", path: "../Outside.cbz"),
                ],
                from: harness.descriptor
            )
        ) { error in
            guard let removalError = error as? LibraryComicRemovalError,
                  case .unsafeComicPath = removalError else {
                return XCTFail("Expected unsafeComicPath, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: safeURL), Data([8]))
        XCTAssertEqual(try Data(contentsOf: outsideURL), Data([9]))
        XCTAssertEqual(fileManager.moveCallCount, 0)
        XCTAssertEqual(databaseWriter.deleteCallCount, 0)
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    func testDanglingSymlinkBehindEscapingParentSymlinkIsRejected() throws {
        let harness = try makeHarness()
        let outsideRootURL = harness.rootURL.appendingPathComponent("Outside", isDirectory: true)
        try harness.fileManager.createDirectory(
            at: outsideRootURL,
            withIntermediateDirectories: true
        )
        let outsideComicURL = outsideRootURL.appendingPathComponent("Comic.cbz")
        try harness.fileManager.createSymbolicLink(
            atPath: outsideComicURL.path,
            withDestinationPath: "Missing.cbz"
        )
        let escapingDirectoryURL = harness.sourceRootURL.appendingPathComponent("Escape")
        try harness.fileManager.createSymbolicLink(
            at: escapingDirectoryURL,
            withDestinationURL: outsideRootURL
        )
        let fileManager = FailureInjectingRemovalFileManager(base: harness.fileManager)
        let databaseWriter = RecordingComicDatabaseDeleter()

        XCTAssertThrowsError(
            try makeService(
                harness: harness,
                databaseWriter: databaseWriter,
                fileManager: fileManager
            ).removeComic(
                makeComic(id: 99, fileName: "Comic.cbz", path: "Escape/Comic.cbz"),
                from: harness.descriptor
            )
        ) { error in
            guard let removalError = error as? LibraryComicRemovalError,
                  case .unsafeComicPath = removalError else {
                return XCTFail("Expected unsafeComicPath, got \(error)")
            }
        }

        XCTAssertEqual(
            try harness.fileManager.destinationOfSymbolicLink(atPath: outsideComicURL.path),
            "Missing.cbz"
        )
        XCTAssertEqual(fileManager.moveCallCount, 0)
        XCTAssertEqual(databaseWriter.deleteCallCount, 0)
        XCTAssertEqual(try quarantineDirectoryNames(in: harness), [])
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func makeStorageManager(_ harness: LibraryDatabaseTestHarness) -> LibraryStorageManager {
        LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
    }

    private func makeService(
        harness: LibraryDatabaseTestHarness,
        databaseWriter: any LibraryComicDatabaseDeleting,
        fileManager: any LibraryComicRemovalFileManaging
    ) -> LibraryComicRemovalService {
        LibraryComicRemovalService(
            storageManager: makeStorageManager(harness),
            databaseWriter: databaseWriter,
            coverLocator: LibraryCoverLocator(fileManager: harness.fileManager),
            fileManager: fileManager
        )
    }

    private func scanAndLoadComics(
        _ harness: LibraryDatabaseTestHarness
    ) throws -> [LibraryComic] {
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: harness.databaseURL
        )
        return try harness.makeReader()
            .loadAllComics(databaseURL: harness.databaseURL)
            .sorted { $0.fileName < $1.fileName }
    }

    private func quarantineDirectoryNames(
        in harness: LibraryDatabaseTestHarness
    ) throws -> [String] {
        try harness.fileManager
            .contentsOfDirectory(
                at: harness.sourceRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            .filter { $0.lastPathComponent.hasPrefix(".jamreader-removal-") }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func makeComic(
        id: Int64,
        fileName: String,
        path: String
    ) -> LibraryComic {
        LibraryComic(
            id: id,
            parentID: 0,
            fileName: fileName,
            path: path,
            hash: "hash-\(id)",
            title: nil,
            issueNumber: nil,
            currentPage: 0,
            pageCount: nil,
            fileSizeBytes: nil,
            bookmarkPageIndices: [],
            read: false,
            hasBeenOpened: false,
            coverSizeRatio: nil,
            lastOpenedAt: nil,
            addedAt: nil,
            type: .comic,
            series: nil,
            volume: nil,
            rating: nil,
            isFavorite: false
        )
    }
}

private enum TestFailure: Error {
    case move(Int)
    case remove
    case database
}

private final class RecordingComicDatabaseDeleter: LibraryComicDatabaseDeleting {
    private let error: Error?
    var onDelete: (([Int64], URL) throws -> Void)?
    private(set) var deletedComicIDs: [[Int64]] = []

    var deleteCallCount: Int {
        deletedComicIDs.count
    }

    init(error: Error? = nil) {
        self.error = error
    }

    func deleteComics(
        _ comicIDs: [Int64],
        in databaseURL: URL
    ) throws {
        deletedComicIDs.append(comicIDs)
        try onDelete?(comicIDs, databaseURL)
        if let error {
            throw error
        }
    }
}

private final class FailureInjectingRemovalFileManager: LibraryComicRemovalFileManaging {
    private let base: FileManager
    private let failingMoveNumber: Int?
    private let failingRemovalURL: URL?
    private(set) var moveCallCount = 0

    init(
        base: FileManager,
        failingMoveNumber: Int? = nil,
        failingRemovalURL: URL? = nil
    ) {
        self.base = base
        self.failingMoveNumber = failingMoveNumber
        self.failingRemovalURL = failingRemovalURL?.standardizedFileURL
    }

    func fileExists(atPath path: String) -> Bool {
        base.fileExists(atPath: path)
    }

    func destinationOfSymbolicLink(atPath path: String) throws -> String {
        try base.destinationOfSymbolicLink(atPath: path)
    }

    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try base.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moveCallCount += 1
        if moveCallCount == failingMoveNumber {
            throw TestFailure.move(moveCallCount)
        }
        try base.moveItem(at: srcURL, to: dstURL)
    }

    func removeItem(at url: URL) throws {
        if url.standardizedFileURL == failingRemovalURL {
            throw TestFailure.remove
        }
        try base.removeItem(at: url)
    }
}
