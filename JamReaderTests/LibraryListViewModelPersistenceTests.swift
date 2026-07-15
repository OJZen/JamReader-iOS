import XCTest
@testable import JamReader

@MainActor
final class LibraryListViewModelPersistenceTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        harnesses.forEach { $0.remove() }
        harnesses.removeAll()
        super.tearDown()
    }

    func testRenameFailureDoesNotPolluteNextRenameCandidate() throws {
        let harness = try makeHarness()
        let store = ControlledLibraryDescriptorStore(fileManager: harness.fileManager)
        let viewModel = makeViewModel(harness: harness, store: store)
        store.failNextSave()

        XCTAssertFalse(viewModel.renameLibrary(id: harness.descriptor.id, to: "Failed Rename"))
        XCTAssertEqual(viewModel.items.first?.descriptor.name, harness.descriptor.name)

        XCTAssertTrue(viewModel.renameLibrary(id: harness.descriptor.id, to: "Saved Rename"))
        XCTAssertEqual(viewModel.items.first?.descriptor.name, "Saved Rename")
        XCTAssertEqual(try store.load().first?.name, "Saved Rename")
    }

    func testAddFolderFailureDoesNotMakeRetryLookLikeDuplicate() throws {
        let harness = try makeHarness()
        let store = ControlledLibraryDescriptorStore(fileManager: harness.fileManager)
        let viewModel = makeViewModel(harness: harness, store: store)
        let linkedFolderURL = harness.rootURL.appendingPathComponent("Second Library", isDirectory: true)
        try harness.fileManager.createDirectory(at: linkedFolderURL, withIntermediateDirectories: true)
        let assetsBeforeFailure = try libraryAssetDirectoryNames(harness: harness)
        store.failNextSave()

        viewModel.addLibraryFolders(from: [linkedFolderURL])
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(try libraryAssetDirectoryNames(harness: harness), assetsBeforeFailure)

        viewModel.addLibraryFolders(from: [linkedFolderURL])
        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertTrue(viewModel.items.contains { $0.descriptor.sourcePath == linkedFolderURL.path })
    }

    func testCreateFailureDoesNotReserveNameInMemory() throws {
        let harness = try makeHarness()
        let store = ControlledLibraryDescriptorStore(fileManager: harness.fileManager)
        let viewModel = makeViewModel(harness: harness, store: store)
        let assetsBeforeFailure = try libraryAssetDirectoryNames(harness: harness)
        store.failNextSave()

        XCTAssertNil(viewModel.createLibrary(named: "Retry Library"))
        XCTAssertFalse(viewModel.items.contains { $0.descriptor.name == "Retry Library" })
        XCTAssertEqual(try libraryAssetDirectoryNames(harness: harness), assetsBeforeFailure)

        let createdID = try XCTUnwrap(
            viewModel.createLibrary(named: "Retry Library"),
            viewModel.alert?.message ?? "Missing create error"
        )
        XCTAssertTrue(viewModel.items.contains { $0.id == createdID && $0.descriptor.name == "Retry Library" })
        XCTAssertTrue(try store.load().contains { $0.id == createdID })
    }

    func testCreateScanRollbackFailureKeepsRecoverableFiles() throws {
        let harness = try makeHarness()
        let store = ControlledLibraryDescriptorStore(fileManager: harness.fileManager)
        let viewModel = makeViewModel(
            harness: harness,
            store: store,
            libraryScanner: FailingLibraryScanner(base: harness.makeScanner())
        )
        store.failSave(afterSuccessfulSaves: 1)

        XCTAssertNil(viewModel.createLibrary(named: "Recoverable Library"))

        let retainedDescriptor = try XCTUnwrap(
            try store.load().first { $0.name == "Recoverable Library" }
        )
        XCTAssertTrue(harness.fileManager.fileExists(atPath: retainedDescriptor.rootPath))
        XCTAssertTrue(
            harness.fileManager.fileExists(
                atPath: LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
                    .metadataRootURL(for: retainedDescriptor)
                    .path
            )
        )
        XCTAssertEqual(
            viewModel.alert?.message,
            "Library setup failed, and its catalog entry could not be rolled back. Local files were kept for recovery."
        )
    }

    func testStorageManagerDeletesCandidateLibraryAssets() throws {
        let harness = try makeHarness()
        let storageManager = LibraryStorageManager(
            fileManager: harness.fileManager,
            database: harness.database
        )
        let candidateURL = harness.rootURL.appendingPathComponent("Candidate", isDirectory: true)
        try harness.fileManager.createDirectory(at: candidateURL, withIntermediateDirectories: true)
        let descriptor = try storageManager.registerLibrary(at: candidateURL)
        let assetsURL = storageManager.metadataRootURL(for: descriptor)
        XCTAssertTrue(harness.fileManager.fileExists(atPath: assetsURL.path))

        storageManager.deleteLibraryAssets(for: descriptor)

        XCTAssertFalse(harness.fileManager.fileExists(atPath: assetsURL.path))
    }

    func testLibraryMutationsAreRejectedWhileSharedStorageGateIsBusy() throws {
        let harness = try makeHarness()
        let store = ControlledLibraryDescriptorStore(fileManager: harness.fileManager)
        let controller = RemoteBackgroundImportController()
        let viewModel = makeViewModel(
            harness: harness,
            store: store,
            remoteBackgroundImportController: controller
        )
        let linkedFolderURL = harness.rootURL.appendingPathComponent("Blocked Add", isDirectory: true)
        try harness.fileManager.createDirectory(at: linkedFolderURL, withIntermediateDirectories: true)
        let comicURL = try harness.writeFile("BlockedImport.cbz", bytes: [1, 2, 3])
        XCTAssertTrue(controller.beginExclusiveStorageMaintenance())
        defer {
            controller.endExclusiveStorageMaintenance()
        }

        viewModel.addLibraryFolders(from: [linkedFolderURL])
        XCTAssertNil(viewModel.createLibrary(named: "Blocked Create"))
        XCTAssertFalse(viewModel.renameLibrary(id: harness.descriptor.id, to: "Blocked Rename"))
        XCTAssertFalse(viewModel.removeLibrary(id: harness.descriptor.id))
        viewModel.importComicFiles(from: [comicURL])

        XCTAssertEqual(viewModel.items.map(\.id), [harness.descriptor.id])
        XCTAssertFalse(viewModel.isImporting)
        XCTAssertEqual(viewModel.alert?.title, "Library Busy")
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func makeViewModel(
        harness: LibraryDatabaseTestHarness,
        store: ControlledLibraryDescriptorStore,
        libraryScanner: (any LibraryScanning)? = nil,
        remoteBackgroundImportController: RemoteBackgroundImportController? = nil
    ) -> LibraryListViewModel {
        let storageManager = LibraryStorageManager(
            fileManager: harness.fileManager,
            database: harness.database
        )
        return LibraryListViewModel(
            store: store,
            storageManager: storageManager,
            inspector: SQLiteDatabaseInspector(fileManager: harness.fileManager),
            databaseBootstrapper: LibraryDatabaseBootstrapper(fileManager: harness.fileManager),
            libraryScanner: libraryScanner ?? harness.makeScanner(),
            maintenanceStatusStore: LibraryMaintenanceStatusStore(fileManager: harness.fileManager),
            importedComicsImportService: harness.makeImportedComicsImportService(),
            remoteBackgroundImportController: remoteBackgroundImportController ?? RemoteBackgroundImportController()
        )
    }

    private func libraryAssetDirectoryNames(
        harness: LibraryDatabaseTestHarness
    ) throws -> [String] {
        let assetsRootURL = try harness.database
            .storageRootURL()
            .appendingPathComponent("LibraryAssets", isDirectory: true)
        guard harness.fileManager.fileExists(atPath: assetsRootURL.path) else {
            return []
        }

        return try harness.fileManager.contentsOfDirectory(atPath: assetsRootURL.path).sorted()
    }
}

private final class ControlledLibraryDescriptorStore: LibraryDescriptorStoring {
    private let underlyingStore: LibraryDescriptorStore
    private var saveAttemptCount = 0
    private var failingSaveAttempts = Set<Int>()

    init(fileManager: FileManager) {
        self.underlyingStore = LibraryDescriptorStore(fileManager: fileManager)
    }

    func load() throws -> [LibraryDescriptor] {
        try underlyingStore.load()
    }

    func save(_ descriptors: [LibraryDescriptor]) throws {
        saveAttemptCount += 1
        if failingSaveAttempts.remove(saveAttemptCount) != nil {
            throw ControlledStoreError.saveFailed
        }
        try underlyingStore.save(descriptors)
    }

    func failNextSave() {
        failingSaveAttempts.insert(saveAttemptCount + 1)
    }

    func failSave(afterSuccessfulSaves successfulSaveCount: Int) {
        failingSaveAttempts.insert(saveAttemptCount + successfulSaveCount + 1)
    }
}

private final class FailingLibraryScanner: LibraryScanning, @unchecked Sendable {
    private let base: any LibraryScanning

    init(base: any LibraryScanning) {
        self.base = base
    }

    func scanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        throw ControlledScannerError.scanFailed
    }

    func rescanLibrary(
        sourceRootURL: URL,
        databaseURL: URL,
        cancellationCheck: (() throws -> Void)?,
        progressHandler: ((LibraryScanProgress) -> Void)?
    ) throws -> LibraryScanSummary {
        try base.rescanLibrary(
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
        try base.refreshFolder(
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
}

private enum ControlledStoreError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        "Injected save failure"
    }
}

private enum ControlledScannerError: LocalizedError {
    case scanFailed

    var errorDescription: String? {
        "Injected scan failure"
    }
}
