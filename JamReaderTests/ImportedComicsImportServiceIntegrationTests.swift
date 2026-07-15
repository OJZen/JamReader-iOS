import XCTest
@testable import JamReader

final class ImportedComicsImportServiceIntegrationTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        for harness in harnesses {
            harness.remove()
        }
        harnesses.removeAll()
        super.tearDown()
    }

    func testImportSingleFileCreatesImportedLibraryCopiesFileAndIndexesIt() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Source.cbz", bytes: [1, 2, 3], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertTrue(result.createdLibrary)
        XCTAssertEqual(result.importedDestinationName, ImportedComicsImportService.defaultImportedComicsLibraryName)
        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertEqual(result.scanSummary?.comicCount, 1)
        XCTAssertEqual(result.unsupportedItemNames, [])
        XCTAssertEqual(result.failedItemNames, [])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        let copiedURL = importedRootURL.appendingPathComponent("Source.cbz")
        XCTAssertTrue(harness.fileManager.fileExists(atPath: copiedURL.path))
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data([1, 2, 3]))

        let comics = try importedComics(for: importedLibrary, harness: harness)
        XCTAssertEqual(comics.map(\.fileName), ["Source.cbz"])
        XCTAssertEqual(comics.compactMap(\.path), ["/Source.cbz"])
    }

    func testImportingSameFileTwiceReusesExistingDestinationWithoutDuplicateCopies() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Repeated.cbz", bytes: [7, 8, 9], harness: harness)
        let service = harness.makeImportedComicsImportService()

        _ = try service.importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )
        let secondResult = try service.importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(secondResult.importedComicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.comicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.reusedComicCount, 1)

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertEqual(
            try regularFileNames(in: importedRootURL, harness: harness),
            ["Repeated.cbz"]
        )
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["Repeated.cbz"]
        )
    }

    func testImportingDifferentFileWithSameNameCreatesUniqueDestinationAndIndexesBoth() throws {
        let harness = try makeHarness()
        let firstSourceDirectory = try createSourceDirectory("First", harness: harness)
        let secondSourceDirectory = try createSourceDirectory("Second", harness: harness)
        let firstURL = try writeFile("Same.cbz", in: firstSourceDirectory, using: harness.fileManager, bytes: [1, 1, 1])
        let secondURL = try writeFile("Same.cbz", in: secondSourceDirectory, using: harness.fileManager, bytes: [2, 2, 2])
        let service = harness.makeImportedComicsImportService()

        _ = try service.importComicResources(
            from: [firstURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )
        let secondResult = try service.importComicResources(
            from: [secondURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(secondResult.importedComicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.comicCount, 2)

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertEqual(
            try regularFileNames(in: importedRootURL, harness: harness),
            ["Same (1).cbz", "Same.cbz"]
        )
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["Same (1).cbz", "Same.cbz"]
        )
    }

    func testDirectoryImportTraversesSupportedFilesAndImageDirectoryComics() throws {
        let harness = try makeHarness()
        let sourceDirectoryURL = try createSourceDirectory("Batch", harness: harness)
        try writeFile("Folder/Issue.cbz", in: sourceDirectoryURL, using: harness.fileManager, bytes: [1])
        try writeFile("Folder/Notes.txt", in: sourceDirectoryURL, using: harness.fileManager, bytes: [2])
        try writeFile("Folder/Image Comic/002.png", in: sourceDirectoryURL, using: harness.fileManager, bytes: [3])
        try writeFile("Folder/Image Comic/001.jpg", in: sourceDirectoryURL, using: harness.fileManager, bytes: [4])

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceDirectoryURL],
            traverseDirectories: true,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(result.importedComicCount, 2)
        XCTAssertEqual(result.scanSummary?.comicCount, 2)
        XCTAssertEqual(result.unsupportedItemNames, [])
        XCTAssertEqual(result.failedItemNames, [])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let comics = try importedComics(for: importedLibrary, harness: harness)
        XCTAssertEqual(comics.map(\.fileName), ["Image Comic", "Issue.cbz"])
        XCTAssertEqual(
            comics.compactMap(\.path).sorted(),
            ["/Image Comic", "/Issue.cbz"]
        )
        XCTAssertEqual(comics.first { $0.fileName == "Image Comic" }?.pageCount, 2)
    }

    func testLargeImportPerformsOneFinalIndexScan() throws {
        let harness = try makeHarness()
        let sourceURLs = try (0..<17).map { index in
            try writeSourceFile(
                String(format: "Issue-%02d.cbz", index),
                bytes: [UInt8(index)],
                harness: harness
            )
        }
        let scanner = CountingLibraryScanner(base: harness.makeScanner())

        let result = try makeImportService(
            harness: harness,
            libraryScanner: scanner
        ).importComicResources(
            from: sourceURLs,
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            cancellationCheck: {}
        )

        XCTAssertEqual(result.importedComicCount, 17)
        XCTAssertEqual(result.scanSummary?.comicCount, 17)
        XCTAssertEqual(scanner.appendCancellationCheckPresence, [true])
        XCTAssertEqual(scanner.fullScanInvocationCount, 1)
    }

    func testImportIntoSelectedLibraryCopiesAndIndexesWithinThatLibraryOnly() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Selected.cbz", bytes: [5, 6, 7], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            destinationSelection: .library(harness.descriptor.id)
        )

        XCTAssertFalse(result.createdLibrary)
        XCTAssertEqual(result.importedDestinationID, harness.descriptor.id)
        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertEqual(result.scanSummary?.comicCount, 1)
        XCTAssertEqual(
            try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL).map(\.fileName),
            ["Selected.cbz"]
        )
        XCTAssertEqual(try LibraryDescriptorStore(fileManager: harness.fileManager).load().map(\.kind), [.linkedFolder])
    }

    func testImportIntoSelectedLibrarySubfolderIndexesRelativePath() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Nested.cbz", bytes: [5, 6, 7], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            destinationSelection: .library(harness.descriptor.id),
            destinationRelativePath: "Series/Volume 1"
        )

        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertTrue(
            harness.fileManager.fileExists(
                atPath: harness.sourceRootURL
                    .appendingPathComponent("Series/Volume 1/Nested.cbz")
                    .path
            )
        )
        XCTAssertEqual(
            try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL).compactMap(\.path),
            ["/Series/Volume 1/Nested.cbz"]
        )
    }

    func testImportRejectsDestinationPathOutsideLibraryRoot() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Escape.cbz", bytes: [1], harness: harness)

        XCTAssertThrowsError(
            try harness.makeImportedComicsImportService().importComicResources(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                destinationSelection: .library(harness.descriptor.id),
                destinationRelativePath: "../../Outside"
            )
        ) { error in
            guard let validationError = error as? ImportedComicsImportService.ImportDestinationValidationError,
                  case .destinationFolderOutsideLibrary = validationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testImportRejectsDestinationSymlinkOutsideLibraryRoot() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("EscapeSymlink.cbz", bytes: [1], harness: harness)
        let outsideDirectoryURL = harness.rootURL.appendingPathComponent("OutsideDestination", isDirectory: true)
        try harness.fileManager.createDirectory(at: outsideDirectoryURL, withIntermediateDirectories: true)
        let symlinkURL = harness.sourceRootURL.appendingPathComponent("Escaped", isDirectory: true)
        try harness.fileManager.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: outsideDirectoryURL
        )

        XCTAssertThrowsError(
            try harness.makeImportedComicsImportService().importComicResources(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                destinationSelection: .library(harness.descriptor.id),
                destinationRelativePath: "Escaped"
            )
        ) { error in
            guard let validationError = error as? ImportedComicsImportService.ImportDestinationValidationError,
                  case .destinationFolderOutsideLibrary = validationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(
            try harness.fileManager.contentsOfDirectory(atPath: outsideDirectoryURL.path),
            []
        )
    }

    func testCancellationInsideSingleItemImportIsNotReportedAsItemFailure() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Cancel.cbz", bytes: [1, 2, 3], harness: harness)
        var cancellationCheckCount = 0

        XCTAssertThrowsError(
            try harness.makeImportedComicsImportService().importComicResources(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                cancellationCheck: {
                    cancellationCheckCount += 1
                    if cancellationCheckCount == 4 {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancellationAfterTransferRunsOneUncancellableCompensationScan() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("TransferCancel.cbz", bytes: [1, 2, 3], harness: harness)
        let scanner = CountingLibraryScanner(base: harness.makeScanner())
        var shouldCancel = false

        XCTAssertThrowsError(
            try makeImportService(
                harness: harness,
                libraryScanner: scanner
            ).importComicResources(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                progressHandler: { progress in
                    if progress.phase == .transferring {
                        shouldCancel = true
                    }
                },
                cancellationCheck: {
                    if shouldCancel {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(scanner.appendCancellationCheckPresence, [false])
        XCTAssertEqual(scanner.fullScanInvocationCount, 1)
        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["TransferCancel.cbz"]
        )
    }

    func testCancellationDuringIndexingRunsCompensationIndex() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("IndexCancel.cbz", bytes: [1, 2, 3], harness: harness)
        let scanner = CountingLibraryScanner(base: harness.makeScanner())
        var shouldCancel = false
        var observedIndexing = false

        XCTAssertThrowsError(
            try makeImportService(
                harness: harness,
                libraryScanner: scanner
            ).importComicResources(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                progressHandler: { progress in
                    guard progress.phase == .indexing, !observedIndexing else {
                        return
                    }
                    observedIndexing = true
                    shouldCancel = true
                },
                cancellationCheck: {
                    if shouldCancel {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertTrue(observedIndexing)
        XCTAssertEqual(scanner.appendCancellationCheckPresence, [true, false])
        XCTAssertEqual(scanner.fullScanInvocationCount, 2)
        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["IndexCancel.cbz"]
        )
    }

    func testFingerprintChecksCancellationBetweenChunks() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile(
            "Large.cbz",
            bytes: (0..<32).map(UInt8.init),
            harness: harness
        )
        var cancellationCheckCount = 0

        XCTAssertThrowsError(
            try ImportedComicsImportService.importFingerprint(
                for: sourceURL,
                chunkSize: 4,
                cancellationCheck: {
                    cancellationCheckCount += 1
                    if cancellationCheckCount == 3 {
                        throw CancellationError()
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(cancellationCheckCount, 3)
    }

    func testCancellingAsyncImportTaskPropagatesCancellation() async throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("AsyncCancel.cbz", bytes: [1, 2, 3], harness: harness)
        let reachedTransfer = expectation(description: "Reached transfer progress")
        let allowImportToContinue = DispatchSemaphore(value: 0)
        let progressLock = NSLock()
        var didBlockProgress = false

        let task = Task {
            try await harness.makeImportedComicsImportService().importComicResourcesAsync(
                from: [sourceURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                progressHandler: { _ in
                    progressLock.lock()
                    let shouldBlock = !didBlockProgress
                    didBlockProgress = true
                    progressLock.unlock()

                    if shouldBlock {
                        reachedTransfer.fulfill()
                        allowImportToContinue.wait()
                    }
                }
            )
        }

        await fulfillment(of: [reachedTransfer], timeout: 5)
        task.cancel()
        allowImportToContinue.signal()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["AsyncCancel.cbz"]
        )
    }

    func testConsumeSourceURLsMovesImportedFileIntoDestination() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("MoveMe.cbz", bytes: [8, 9, 10], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            consumeSourceURLs: [sourceURL.standardizedFileURL]
        )

        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertFalse(harness.fileManager.fileExists(atPath: sourceURL.path))

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertTrue(harness.fileManager.fileExists(atPath: importedRootURL.appendingPathComponent("MoveMe.cbz").path))
    }

    func testNonTraversedNonComicDirectoryIsReportedUnsupported() throws {
        let harness = try makeHarness()
        let sourceDirectoryURL = try createSourceDirectory("Plain Folder", harness: harness)
        try writeFile("Readme.txt", in: sourceDirectoryURL, using: harness.fileManager, bytes: [1])

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceDirectoryURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertTrue(result.createdLibrary)
        XCTAssertEqual(result.importedComicCount, 0)
        XCTAssertNil(result.scanSummary)
        XCTAssertEqual(result.unsupportedItemNames, ["Plain Folder"])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        XCTAssertEqual(try importedComics(for: importedLibrary, harness: harness), [])
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func makeImportService(
        harness: LibraryDatabaseTestHarness,
        libraryScanner: any LibraryScanning
    ) -> ImportedComicsImportService {
        ImportedComicsImportService(
            store: LibraryDescriptorStore(fileManager: harness.fileManager),
            storageManager: LibraryStorageManager(
                fileManager: harness.fileManager,
                database: harness.database
            ),
            databaseBootstrapper: LibraryDatabaseBootstrapper(fileManager: harness.fileManager),
            libraryScanner: libraryScanner,
            maintenanceStatusStore: LibraryMaintenanceStatusStore(fileManager: harness.fileManager),
            directoryImageSequenceInspector: DirectoryImageSequenceInspector(fileManager: harness.fileManager),
            fileManager: harness.fileManager,
            databaseInspector: SQLiteDatabaseInspector(fileManager: harness.fileManager),
            databaseReader: LibraryDatabaseReader(fileManager: harness.fileManager)
        )
    }

    private func importedLibraryDescriptor(harness: LibraryDatabaseTestHarness) throws -> LibraryDescriptor {
        let descriptors = try LibraryDescriptorStore(fileManager: harness.fileManager).load()
        return try XCTUnwrap(descriptors.first { $0.kind == .importedComics })
    }

    private func importedRootURL(
        for descriptor: LibraryDescriptor,
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        try LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
            .restoreSourceURL(for: descriptor)
            .standardizedFileURL
    }

    private func importedComics(
        for descriptor: LibraryDescriptor,
        harness: LibraryDatabaseTestHarness
    ) throws -> [LibraryComic] {
        let storageManager = LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
        return try LibraryDatabaseReader(fileManager: harness.fileManager)
            .loadAllComics(databaseURL: storageManager.databaseURL(for: descriptor))
    }

    private func regularFileNames(
        in directoryURL: URL,
        harness: LibraryDatabaseTestHarness
    ) throws -> [String] {
        try harness.fileManager
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func writeSourceFile(
        _ relativePath: String,
        bytes: [UInt8],
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        let sourceDirectoryURL = try createSourceDirectory("ImportSources", harness: harness)
        return try writeFile(relativePath, in: sourceDirectoryURL, using: harness.fileManager, bytes: bytes)
    }

    private func createSourceDirectory(
        _ relativePath: String,
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        let url = harness.rootURL
            .appendingPathComponent("ExternalSources", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
        try harness.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeFile(
        _ relativePath: String,
        in sourceRootURL: URL,
        using fileManager: FileManager,
        bytes: [UInt8]
    ) throws -> URL {
        let url = sourceRootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: url)
        return url
    }
}

private final class CountingLibraryScanner: LibraryScanning, @unchecked Sendable {
    private let base: any LibraryScanning
    private let lock = NSLock()
    private var storedAppendCancellationCheckPresence: [Bool] = []
    private var storedFullScanInvocationCount = 0

    init(base: any LibraryScanning) {
        self.base = base
    }

    var appendCancellationCheckPresence: [Bool] {
        lock.withLock {
            storedAppendCancellationCheckPresence
        }
    }

    var fullScanInvocationCount: Int {
        lock.withLock {
            storedFullScanInvocationCount
        }
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        recordFullScan()
        return try base.scanLibrary(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func rescanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        recordFullScan()
        return try base.rescanLibrary(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func refreshFolder(
        sourceRootURL: URL,
        databaseURL: URL,
        folder: LibraryFolder,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        recordFullScan()
        return try base.refreshFolder(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            folder: folder,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    func appendImportedComics(
        sourceRootURL: URL,
        databaseURL: URL,
        fileURLs: [URL],
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        lock.withLock {
            storedAppendCancellationCheckPresence.append(cancellationCheck != nil)
            storedFullScanInvocationCount += 1
        }
        return try base.appendImportedComics(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            fileURLs: fileURLs,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    private func recordFullScan() {
        lock.withLock {
            storedFullScanInvocationCount += 1
        }
    }
}
