import XCTest
@testable import JamReader

@MainActor
final class LibraryBrowserViewModelStorageGateTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        harnesses.forEach { $0.remove() }
        harnesses.removeAll()
        super.tearDown()
    }

    func testInitializeHoldsSharedGateUntilSuccessfulScanCompletes() async throws {
        let harness = try makeHarness()
        _ = try harness.writeFile("Issue.cbz")
        let scanStarted = expectation(description: "Initialize scan started")
        let scanner = BlockingLibraryScanner(
            base: harness.makeScanner(),
            blockedOperation: .scan,
            outcome: .delegate,
            started: scanStarted
        )
        let controller = RemoteBackgroundImportController()
        let viewModel = makeViewModel(
            harness: harness,
            libraryScanner: scanner,
            controller: controller
        )

        viewModel.initializeLibrary()
        await fulfillment(of: [scanStarted], timeout: 5)

        XCTAssertTrue(controller.isStorageMaintenanceRunning)
        XCTAssertFalse(
            controller.start { _, _ in
                XCTFail("Remote import must not start while a library scan owns the gate")
            }
        )

        scanner.resume()
        let didReleaseGate = await waitForStorageGateRelease(controller)
        XCTAssertTrue(didReleaseGate)
        XCTAssertFalse(viewModel.isInitializingLibrary)
        XCTAssertEqual(viewModel.lastInitializationSummary?.comicCount, 1)
    }

    func testRefreshLibraryReleasesSharedGateAfterFailure() async throws {
        let harness = try makeIndexedHarness(with: "Issue.cbz")
        let scanStarted = expectation(description: "Library refresh started")
        let scanner = BlockingLibraryScanner(
            base: harness.makeScanner(),
            blockedOperation: .rescan,
            outcome: .failure,
            started: scanStarted
        )
        let controller = RemoteBackgroundImportController()
        let viewModel = makeViewModel(
            harness: harness,
            libraryScanner: scanner,
            controller: controller
        )

        viewModel.refreshLibrary()
        await fulfillment(of: [scanStarted], timeout: 5)
        XCTAssertTrue(controller.isStorageMaintenanceRunning)

        scanner.resume()
        let didReleaseGate = await waitForStorageGateRelease(controller)
        XCTAssertTrue(didReleaseGate)
        XCTAssertFalse(viewModel.isRefreshingLibrary)
        XCTAssertEqual(viewModel.alert?.title, "Failed to Refresh Library")
    }

    func testRefreshCurrentFolderReleasesSharedGateAfterCancellation() async throws {
        let harness = try makeIndexedHarness(with: "Series/Issue.cbz")
        let rootContent = try harness.makeReader().loadFolderContent(
            databaseURL: harness.databaseURL,
            folderID: 1
        )
        let folder = try XCTUnwrap(rootContent.subfolders.first)
        let scanStarted = expectation(description: "Folder refresh started")
        let scanner = BlockingLibraryScanner(
            base: harness.makeScanner(),
            blockedOperation: .refreshFolder,
            outcome: .cancellation,
            started: scanStarted
        )
        let controller = RemoteBackgroundImportController()
        let viewModel = makeViewModel(
            harness: harness,
            folderID: folder.id,
            libraryScanner: scanner,
            controller: controller
        )
        viewModel.load()

        viewModel.refreshCurrentFolder()
        await fulfillment(of: [scanStarted], timeout: 5)
        XCTAssertTrue(controller.isStorageMaintenanceRunning)

        scanner.resume()
        let didReleaseGate = await waitForStorageGateRelease(controller)
        XCTAssertTrue(didReleaseGate)
        XCTAssertFalse(viewModel.isRefreshingLibrary)
        XCTAssertEqual(viewModel.alert?.title, "Failed to Refresh Folder")
    }

    func testScanCompletionReleasesSharedGateAfterViewModelDeallocation() async throws {
        let harness = try makeHarness()
        _ = try harness.writeFile("Issue.cbz")
        let scanStarted = expectation(description: "Initialize scan started")
        let scanner = BlockingLibraryScanner(
            base: harness.makeScanner(),
            blockedOperation: .scan,
            outcome: .delegate,
            started: scanStarted
        )
        let controller = RemoteBackgroundImportController()
        let weakViewModel = WeakReference<LibraryBrowserViewModel>()
        autoreleasepool {
            let viewModel = makeViewModel(
                harness: harness,
                libraryScanner: scanner,
                controller: controller
            )
            weakViewModel.value = viewModel
            viewModel.initializeLibrary()
        }
        await fulfillment(of: [scanStarted], timeout: 5)
        XCTAssertTrue(controller.isStorageMaintenanceRunning)

        XCTAssertNil(weakViewModel.value)

        scanner.resume()
        let didReleaseGate = await waitForStorageGateRelease(controller)
        XCTAssertTrue(didReleaseGate)
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func makeIndexedHarness(
        with relativePath: String,
        testName: String = #function
    ) throws -> LibraryDatabaseTestHarness {
        let harness = try makeHarness(testName: testName)
        _ = try harness.writeFile(relativePath)
        _ = try harness.makeScanner().scanLibrary(
            sourceRootURL: harness.sourceRootURL,
            databaseURL: harness.databaseURL,
            cancellationCheck: nil,
            progressHandler: nil
        )
        return harness
    }

    private func makeViewModel(
        harness: LibraryDatabaseTestHarness,
        folderID: Int64 = 1,
        libraryScanner: any LibraryScanning,
        controller: RemoteBackgroundImportController
    ) -> LibraryBrowserViewModel {
        let storageManager = LibraryStorageManager(
            fileManager: harness.fileManager,
            database: harness.database
        )
        let databaseWriter = LibraryDatabaseWriter(fileManager: harness.fileManager)
        let coverLocator = LibraryCoverLocator(fileManager: harness.fileManager)
        return LibraryBrowserViewModel(
            descriptor: harness.descriptor,
            folderID: folderID,
            storageManager: storageManager,
            databaseReader: LibraryDatabaseReader(fileManager: harness.fileManager),
            databaseWriter: databaseWriter,
            databaseBootstrapper: LibraryDatabaseBootstrapper(fileManager: harness.fileManager),
            libraryScanner: libraryScanner,
            maintenanceStatusStore: LibraryMaintenanceStatusStore(fileManager: harness.fileManager),
            coverLocator: coverLocator,
            comicInfoImportService: ComicInfoImportService(
                storageManager: storageManager,
                databaseWriter: databaseWriter
            ),
            importedComicsImportService: harness.makeImportedComicsImportService(),
            comicRemovalService: LibraryComicRemovalService(
                storageManager: storageManager,
                databaseWriter: databaseWriter,
                coverLocator: coverLocator,
                fileManager: harness.fileManager
            ),
            remoteBackgroundImportController: controller,
            databaseInspector: SQLiteDatabaseInspector(fileManager: harness.fileManager)
        )
    }

    private func waitForStorageGateRelease(
        _ controller: RemoteBackgroundImportController,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while controller.isStorageMaintenanceRunning, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return !controller.isStorageMaintenanceRunning
    }
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?
}

private final class BlockingLibraryScanner: LibraryScanning, @unchecked Sendable {
    enum Operation: Equatable {
        case scan
        case rescan
        case refreshFolder
    }

    enum Outcome {
        case delegate
        case failure
        case cancellation
    }

    private let base: any LibraryScanning
    private let blockedOperation: Operation
    private let outcome: Outcome
    private let started: XCTestExpectation
    private let resumeSemaphore = DispatchSemaphore(value: 0)

    init(
        base: any LibraryScanning,
        blockedOperation: Operation,
        outcome: Outcome,
        started: XCTestExpectation
    ) {
        self.base = base
        self.blockedOperation = blockedOperation
        self.outcome = outcome
        self.started = started
    }

    func resume() {
        resumeSemaphore.signal()
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        try blockIfNeeded(.scan)
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
        try blockIfNeeded(.rescan)
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
        try blockIfNeeded(.refreshFolder)
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
        try base.appendImportedComics(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            fileURLs: fileURLs,
            cancellationCheck: cancellationCheck,
            progressHandler: progressHandler
        )
    }

    private func blockIfNeeded(_ operation: Operation) throws {
        guard operation == blockedOperation else {
            return
        }

        started.fulfill()
        resumeSemaphore.wait()

        switch outcome {
        case .delegate:
            return
        case .failure:
            throw StorageGateScannerError.injectedFailure
        case .cancellation:
            throw CancellationError()
        }
    }
}

private enum StorageGateScannerError: LocalizedError {
    case injectedFailure

    var errorDescription: String? {
        "Injected scan failure"
    }
}
