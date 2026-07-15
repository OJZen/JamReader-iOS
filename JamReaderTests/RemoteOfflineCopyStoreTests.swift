import XCTest
@testable import JamReader

final class RemoteOfflineCopyStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDownloadedRecordsPersistWithoutReadingHistoryLimit() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = makeOfflineCopyStore(directoryURL: directoryURL)
        let profile = makeProfile()
        let savedAt = Date(timeIntervalSince1970: 1_000)
        let references = (0..<250).map { index in
            makeReference(
                profile: profile,
                path: "/Series/Book-\(index).cbz",
                fileName: "Book-\(index).cbz"
            )
        }

        try store.recordDownloadedCopies(for: references, savedAt: savedAt)

        let reloadedRecords = try makeOfflineCopyStore(directoryURL: directoryURL).loadRecords()
        XCTAssertEqual(reloadedRecords.count, 250)
        XCTAssertEqual(Set(reloadedRecords.map(\.id)), Set(references.map(\.id)))
    }

    func testExistingCacheRecoveryRunsOnlyOnce() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = makeOfflineCopyStore(directoryURL: directoryURL)
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Legacy/Book.cbz",
            fileName: "Book.cbz"
        )
        let record = RemoteOfflineCopyRecord(
            reference: reference,
            savedAt: Date(timeIntervalSince1970: 200)
        )
        var migrationCallCount = 0

        XCTAssertEqual(
            try store.loadRecords {
                migrationCallCount += 1
                return [record]
            }.map(\.id),
            [record.id]
        )

        try store.removeCopy(for: reference)

        XCTAssertEqual(
            try store.loadRecords {
                migrationCallCount += 1
                return [record]
            },
            []
        )
        XCTAssertEqual(migrationCallCount, 1)
    }

    func testCorruptStorageIsQuarantinedAndRecoveredFromExistingCache() throws {
        let directoryURL = try makeTemporaryDirectory()
        let storage = FileBackedJSONStore(
            fileName: "remote_offline_copies.json",
            storageDirectoryURL: directoryURL
        )
        try Data("not-json".utf8).write(to: storage.storageFileURL())
        let store = RemoteOfflineCopyStore(storage: storage)
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Recovered.cbz",
            fileName: "Recovered.cbz"
        )

        let records = try store.loadRecords {
            [RemoteOfflineCopyRecord(reference: reference)]
        }

        XCTAssertEqual(records.map(\.id), [reference.id])
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        XCTAssertEqual(quarantinedFiles.count, 1)
        XCTAssertEqual(
            try makeOfflineCopyStore(directoryURL: directoryURL).loadRecords().map(\.id),
            [reference.id]
        )
    }

    func testRecordFailureRollsBackOnlyNewlyDownloadedCache() throws {
        enum PersistenceFailure: Error {
            case simulated
        }

        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let downloadedReference = makeReference(
            profile: profile,
            path: "/Downloaded.cbz",
            fileName: "Downloaded.cbz"
        )
        let currentReference = makeReference(
            profile: profile,
            path: "/Current.cbz",
            fileName: "Current.cbz"
        )
        let fallbackReference = makeReference(
            profile: profile,
            path: "/Fallback.cbz",
            fileName: "Fallback.cbz"
        )
        let candidates = [
            RemoteOfflineCopyPersistenceCandidate(
                reference: downloadedReference,
                result: RemoteComicDownloadResult(
                    localFileURL: harness.resolver.cachedFileURL(for: downloadedReference),
                    source: .downloaded,
                    cacheMutation: .createdNew
                )
            ),
            RemoteOfflineCopyPersistenceCandidate(
                reference: currentReference,
                result: RemoteComicDownloadResult(
                    localFileURL: harness.resolver.cachedFileURL(for: currentReference),
                    source: .cachedCurrent
                )
            ),
            RemoteOfflineCopyPersistenceCandidate(
                reference: fallbackReference,
                result: RemoteComicDownloadResult(
                    localFileURL: harness.resolver.cachedFileURL(for: fallbackReference),
                    source: .cachedFallback("Using an existing copy.")
                )
            )
        ]
        for reference in [downloadedReference, currentReference, fallbackReference] {
            try harness.writeCachedComic(for: reference)
        }

        XCTAssertThrowsError(
            try RemoteOfflineCopyPersistenceCoordinator.persist(
                candidates: candidates,
                persistRecords: {
                    throw PersistenceFailure.simulated
                },
                commitDownloadedCache: { _ in
                    XCTFail("A failed record write must not commit staged cache changes")
                },
                rollbackDownloadedCache: { candidate in
                    try harness.browsingService.rollbackDownloadedComicCache(
                        for: candidate.reference,
                        result: candidate.result
                    )
                }
            )
        ) { error in
            XCTAssertTrue(error is PersistenceFailure)
        }

        XCTAssertFalse(
            harness.fileManager.fileExists(
                atPath: harness.resolver.cachedFileURL(for: downloadedReference).path
            )
        )
        XCTAssertTrue(
            harness.fileManager.fileExists(
                atPath: harness.resolver.cachedFileURL(for: currentReference).path
            )
        )
        XCTAssertTrue(
            harness.fileManager.fileExists(
                atPath: harness.resolver.cachedFileURL(for: fallbackReference).path
            )
        )
    }

    func testRecordFailureRestoresReplacedFileCacheAndMetadata() throws {
        enum PersistenceFailure: Error {
            case simulated
        }

        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Replaced.cbz",
            fileName: "Replaced.cbz"
        )
        let destinationURL = harness.resolver.cachedFileURL(for: reference)
        let metadataURL = destinationURL.appendingPathExtension("yacmeta")
        try harness.writeCachedComic(
            for: reference,
            resourceData: Data("old-file".utf8),
            metadataData: Data("old-metadata".utf8)
        )
        let mutation = try harness.browsingService
            .stageCachedComicReplacementForRollback(
                at: destinationURL,
                for: reference
            )
        try Data("new-file".utf8).write(to: destinationURL)
        try Data("new-metadata".utf8).write(to: metadataURL)
        let candidate = RemoteOfflineCopyPersistenceCandidate(
            reference: reference,
            result: RemoteComicDownloadResult(
                localFileURL: destinationURL,
                source: .downloaded,
                cacheMutation: mutation
            )
        )

        XCTAssertThrowsError(
            try RemoteOfflineCopyPersistenceCoordinator.persist(
                candidates: [candidate],
                persistRecords: { throw PersistenceFailure.simulated },
                commitDownloadedCache: { _ in
                    XCTFail("A failed record write must not commit the replacement")
                },
                rollbackDownloadedCache: { candidate in
                    try harness.browsingService.rollbackDownloadedComicCache(
                        for: candidate.reference,
                        result: candidate.result
                    )
                }
            )
        ) { error in
            XCTAssertTrue(error is PersistenceFailure)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("old-file".utf8))
        XCTAssertEqual(try Data(contentsOf: metadataURL), Data("old-metadata".utf8))
        XCTAssertTrue(try rollbackBackupURLs(in: destinationURL.deletingLastPathComponent()).isEmpty)
    }

    func testImportCleanupRestoresReplacedImageDirectoryCache() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Image Comic",
            fileName: "Image Comic",
            fileSize: nil,
            contentKind: .imageDirectory
        )
        let destinationURL = harness.resolver.cachedFileURL(for: reference)
        let metadataURL = destinationURL.appendingPathExtension("yacmeta")
        try harness.writeCachedComic(
            for: reference,
            resourceData: Data("old-page".utf8),
            metadataData: Data("old-directory-metadata".utf8)
        )
        let mutation = try harness.browsingService
            .stageCachedComicReplacementForRollback(
                at: destinationURL,
                for: reference
            )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        try Data("new-page".utf8).write(
            to: destinationURL.appendingPathComponent("New.jpg")
        )
        try Data("new-directory-metadata".utf8).write(to: metadataURL)
        let result = RemoteComicDownloadResult(
            localFileURL: destinationURL,
            source: .downloaded,
            cacheMutation: mutation
        )

        try harness.browsingService.rollbackDownloadedComicCache(
            for: reference,
            result: result
        )

        XCTAssertEqual(
            try Data(contentsOf: destinationURL.appendingPathComponent("Page.jpg")),
            Data("old-page".utf8)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationURL.appendingPathComponent("New.jpg").path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: metadataURL),
            Data("old-directory-metadata".utf8)
        )
        XCTAssertTrue(try rollbackBackupURLs(in: destinationURL.deletingLastPathComponent()).isEmpty)
    }

    func testImportCleanupRemovesNewCacheButPreservesCachedCurrentCopy() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let newReference = makeReference(
            profile: profile,
            path: "/New.cbz",
            fileName: "New.cbz"
        )
        let currentReference = makeReference(
            profile: profile,
            path: "/Current.cbz",
            fileName: "Current.cbz"
        )
        try harness.writeCachedComic(for: newReference)
        try harness.writeCachedComic(for: currentReference)
        let newURL = harness.resolver.cachedFileURL(for: newReference)
        let currentURL = harness.resolver.cachedFileURL(for: currentReference)

        try harness.browsingService.rollbackDownloadedComicCache(
            for: newReference,
            result: RemoteComicDownloadResult(
                localFileURL: newURL,
                source: .downloaded,
                cacheMutation: .createdNew
            )
        )
        try harness.browsingService.rollbackDownloadedComicCache(
            for: currentReference,
            result: RemoteComicDownloadResult(
                localFileURL: currentURL,
                source: .cachedCurrent
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: newURL.appendingPathExtension("yacmeta").path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentURL.path))
    }

    func testSuccessfulRecordPersistenceCommitsReplacementBackup() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Committed.cbz",
            fileName: "Committed.cbz"
        )
        let destinationURL = harness.resolver.cachedFileURL(for: reference)
        try harness.writeCachedComic(
            for: reference,
            resourceData: Data("old".utf8)
        )
        let mutation = try harness.browsingService
            .stageCachedComicReplacementForRollback(
                at: destinationURL,
                for: reference
            )
        try Data("new".utf8).write(to: destinationURL)
        let candidate = RemoteOfflineCopyPersistenceCandidate(
            reference: reference,
            result: RemoteComicDownloadResult(
                localFileURL: destinationURL,
                source: .downloaded,
                cacheMutation: mutation
            )
        )

        try RemoteOfflineCopyPersistenceCoordinator.persist(
            candidates: [candidate],
            persistRecords: {
                try harness.offlineCopyStore.recordDownloadedCopy(for: reference)
            },
            commitDownloadedCache: { candidate in
                try harness.browsingService.commitDownloadedComicCache(
                    for: candidate.reference,
                    result: candidate.result
                )
            },
            rollbackDownloadedCache: { _ in
                XCTFail("A successful record write must not roll back the replacement")
            }
        )

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
        XCTAssertTrue(try rollbackBackupURLs(in: destinationURL.deletingLastPathComponent()).isEmpty)
        XCTAssertEqual(try harness.offlineCopyStore.loadRecords().map(\.id), [reference.id])
    }

    func testSnapshotPruningDoesNotDeleteConcurrentSameReferenceUpdate() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Concurrent.cbz",
            fileName: "Concurrent.cbz"
        )
        try harness.profileStore.save([profile])
        try harness.offlineCopyStore.recordDownloadedCopy(
            for: reference,
            savedAt: Date(timeIntervalSince1970: 10)
        )

        let reachedPruneBarrier = DispatchSemaphore(value: 0)
        let resumePruning = DispatchSemaphore(value: 0)
        let loadFinished = DispatchSemaphore(value: 0)
        let errorBox = OfflineSnapshotErrorBox()
        let snapshotStore = harness.makeSnapshotStore { recordIDs in
            XCTAssertEqual(recordIDs, Set([reference.id]))
            reachedPruneBarrier.signal()
            resumePruning.wait()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try snapshotStore.loadSnapshot(forceRefresh: true)
            } catch {
                errorBox.store(error)
            }
            loadFinished.signal()
        }

        XCTAssertEqual(reachedPruneBarrier.wait(timeout: .now() + 5), .success)
        try harness.writeCachedComic(for: reference)
        try harness.offlineCopyStore.recordDownloadedCopy(
            for: reference,
            savedAt: Date(timeIntervalSince1970: 20)
        )
        resumePruning.signal()
        XCTAssertEqual(loadFinished.wait(timeout: .now() + 5), .success)
        XCTAssertNil(errorBox.load())

        let records = try harness.offlineCopyStore.loadRecords()
        XCTAssertEqual(records.map(\.id), [reference.id])
        XCTAssertEqual(records.first?.savedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(
            try snapshotStore.loadSnapshot(forceRefresh: true).offlineEntries.map(\.recordID),
            [reference.id]
        )
    }

    func testSnapshotDoesNotPruneRecordDuringStagedCacheReplacement() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Refreshing.cbz",
            fileName: "Refreshing.cbz"
        )
        try harness.profileStore.save([profile])
        try harness.writeCachedComic(for: reference)
        try harness.offlineCopyStore.recordDownloadedCopy(for: reference)
        let destinationURL = harness.resolver.cachedFileURL(for: reference)
        let mutation = try harness.browsingService
            .stageCachedComicReplacementForRollback(
                at: destinationURL,
                for: reference
            )
        let result = RemoteComicDownloadResult(
            localFileURL: destinationURL,
            source: .downloaded,
            cacheMutation: mutation
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(
            harness.browsingService.cachedAvailability(for: reference).kind,
            .stale
        )
        XCTAssertEqual(
            try harness.snapshotStore.loadSnapshot(forceRefresh: true)
                .offlineEntries.map(\.recordID),
            [reference.id]
        )
        XCTAssertEqual(try harness.offlineCopyStore.loadRecords().map(\.id), [reference.id])

        try harness.browsingService.rollbackDownloadedComicCache(
            for: reference,
            result: result
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @MainActor
    func testSnapshotRecoversCachedComicWithoutRecordOrReadingSession() throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Never Opened.cbz",
            fileName: "Never Opened.cbz",
            pageCountHint: 24
        )
        try harness.profileStore.save([profile])
        try harness.writeCachedComic(for: reference)

        let firstSnapshot = try harness.snapshotStore.loadSnapshot()
        XCTAssertEqual(firstSnapshot.offlineEntries.count, 1)
        XCTAssertEqual(firstSnapshot.offlineEntries.first?.session.fileName, "Never Opened.cbz")
        XCTAssertEqual(firstSnapshot.offlineEntries.first?.session.hasBeenOpened, false)
        XCTAssertEqual(try harness.offlineCopyStore.loadRecords().count, 1)

        try harness.readingProgressStore.clearAllSessions()
        let refreshedSnapshot = try harness.snapshotStore.loadSnapshot(forceRefresh: true)

        XCTAssertEqual(refreshedSnapshot.offlineEntries.count, 1)
        XCTAssertEqual(refreshedSnapshot.offlineEntries.first?.session.hasBeenOpened, false)
    }

    @MainActor
    func testRefreshFailureRetainsPreviouslyLoadedEntries() async throws {
        let harness = try makeSnapshotHarness()
        let profile = makeProfile()
        let reference = makeReference(
            profile: profile,
            path: "/Saved.cbz",
            fileName: "Saved.cbz"
        )
        try harness.profileStore.save([profile])
        try harness.writeCachedComic(for: reference)
        try harness.offlineCopyStore.recordDownloadedCopy(for: reference)
        let viewModel = RemoteOfflineShelfViewModel(
            remoteOfflineLibrarySnapshotStore: harness.snapshotStore,
            remoteServerBrowsingService: harness.browsingService,
            remoteReadingProgressStore: harness.readingProgressStore,
            remoteOfflineCopyStore: harness.offlineCopyStore,
            remoteBackgroundImportController: RemoteBackgroundImportController()
        )

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.entries.count, 1)

        try Data("invalid-profile-json".utf8).write(to: harness.profileStorage.storageFileURL())
        await viewModel.load(forceRefresh: true)

        guard case .failed = viewModel.loadState else {
            return XCTFail("Expected failed refresh state")
        }
        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.session.fileName, "Saved.cbz")
        XCTAssertNotNil(viewModel.loadFailureMessage)
    }

    @MainActor
    func testInitialLoadFailureDoesNotReportNoDownloadsState() async throws {
        let harness = try makeSnapshotHarness()
        try Data("invalid-profile-json".utf8).write(to: harness.profileStorage.storageFileURL())
        let viewModel = RemoteOfflineShelfViewModel(
            remoteOfflineLibrarySnapshotStore: harness.snapshotStore,
            remoteServerBrowsingService: harness.browsingService,
            remoteReadingProgressStore: harness.readingProgressStore,
            remoteOfflineCopyStore: harness.offlineCopyStore,
            remoteBackgroundImportController: RemoteBackgroundImportController()
        )

        await viewModel.loadIfNeeded()

        guard case .failed = viewModel.loadState else {
            return XCTFail("Expected failed initial load state")
        }
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertFalse(viewModel.isInitialLoading)
        XCTAssertNotNil(viewModel.loadFailureMessage)
    }

    private func makeOfflineCopyStore(directoryURL: URL) -> RemoteOfflineCopyStore {
        RemoteOfflineCopyStore(
            storage: FileBackedJSONStore(
                fileName: "remote_offline_copies.json",
                storageDirectoryURL: directoryURL
            )
        )
    }

    private func makeSnapshotHarness() throws -> OfflineSnapshotTestHarness {
        let rootURL = try makeTemporaryDirectory()
        return try OfflineSnapshotTestHarness(rootURL: rootURL)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOfflineCopyStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func makeProfile() -> RemoteServerProfile {
        RemoteServerProfile(
            id: UUID(uuidString: "62626262-6262-6262-6262-626262626262")!,
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: "Comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeReference(
        profile: RemoteServerProfile,
        path: String,
        fileName: String,
        fileSize: Int64? = 4,
        contentKind: RemoteComicReferenceKind = .file,
        pageCountHint: Int? = nil
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: profile.id,
            providerKind: profile.providerKind,
            shareName: profile.normalizedProviderRootIdentifier,
            cacheScopeKey: profile.remoteCacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: Date(timeIntervalSince1970: 200),
            contentKind: contentKind,
            pageCountHint: pageCountHint,
            coverPath: nil
        )
    }

    private func rollbackBackupURLs(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".jamreader-cache-rollback-") }
    }
}

private final class OfflineSnapshotFileManager: FileManager {
    private let cachesRootURL: URL

    init(cachesRootURL: URL) {
        self.cachesRootURL = cachesRootURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .cachesDirectory && domainMask == .userDomainMask {
            return [cachesRootURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

private struct OfflineSnapshotTestHarness {
    let rootURL: URL
    let fileManager: OfflineSnapshotFileManager
    let resolver: RemoteCachePathResolver
    let profileStorage: FileBackedJSONStore
    let profileStore: RemoteServerProfileStore
    let readingProgressStore: RemoteReadingProgressStore
    let offlineCopyStore: RemoteOfflineCopyStore
    let browsingService: RemoteServerBrowsingService
    let snapshotStore: RemoteOfflineLibrarySnapshotStore

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        let cachesURL = rootURL.appendingPathComponent("Caches", isDirectory: true)
        let storageURL = rootURL.appendingPathComponent("Storage", isDirectory: true)
        let fileManager = OfflineSnapshotFileManager(cachesRootURL: cachesURL)
        let profileStorage = FileBackedJSONStore(
            fileName: "remote_servers.json",
            storageDirectoryURL: storageURL
        )
        let profileStore = RemoteServerProfileStore(storage: profileStorage)
        let readingProgressStore = RemoteReadingProgressStore(
            storage: FileBackedJSONStore(
                fileName: "remote_reading_progress.json",
                storageDirectoryURL: storageURL
            )
        )
        let offlineCopyStore = RemoteOfflineCopyStore(
            storage: FileBackedJSONStore(
                fileName: "remote_offline_copies.json",
                storageDirectoryURL: storageURL
            )
        )
        let remoteComicCacheRootURL = cachesURL
            .appendingPathComponent("JamReader", isDirectory: true)
            .appendingPathComponent("RemoteComics", isDirectory: true)
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: remoteComicCacheRootURL)
        let browsingService = RemoteServerBrowsingService(fileManager: fileManager)

        self.fileManager = fileManager
        self.resolver = resolver
        self.profileStorage = profileStorage
        self.profileStore = profileStore
        self.readingProgressStore = readingProgressStore
        self.offlineCopyStore = offlineCopyStore
        self.browsingService = browsingService
        self.snapshotStore = RemoteOfflineLibrarySnapshotStore(
            remoteServerProfileStore: profileStore,
            remoteReadingProgressStore: readingProgressStore,
            remoteOfflineCopyStore: offlineCopyStore,
            remoteServerBrowsingService: browsingService
        )

        try fileManager.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    func makeSnapshotStore(
        beforeInvalidRecordPruning: ((Set<String>) -> Void)? = nil
    ) -> RemoteOfflineLibrarySnapshotStore {
        RemoteOfflineLibrarySnapshotStore(
            remoteServerProfileStore: profileStore,
            remoteReadingProgressStore: readingProgressStore,
            remoteOfflineCopyStore: offlineCopyStore,
            remoteServerBrowsingService: browsingService,
            beforeInvalidRecordPruning: beforeInvalidRecordPruning
        )
    }

    func writeCachedComic(
        for reference: RemoteComicFileReference,
        resourceData: Data = Data([0, 1, 2, 3]),
        metadataData: Data? = nil
    ) throws {
        let fileURL = resolver.cachedFileURL(for: reference)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if reference.isImageDirectoryComic {
            try fileManager.createDirectory(
                at: fileURL,
                withIntermediateDirectories: true
            )
            try resourceData.write(to: fileURL.appendingPathComponent("Page.jpg"))
        } else {
            try resourceData.write(to: fileURL)
        }
        if let metadataData {
            try metadataData.write(
                to: fileURL.appendingPathExtension("yacmeta"),
                options: .atomic
            )
            return
        }
        let metadata = OfflineSnapshotCachedMetadata(
            cacheScopeKey: reference.cacheScopeKey,
            path: reference.path,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt,
            contentKind: reference.contentKind,
            cachedByteCount: nil
        )
        try JSONEncoder()
            .encode(metadata)
            .write(to: fileURL.appendingPathExtension("yacmeta"), options: .atomic)
    }
}

private final class OfflineSnapshotErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?

    func store(_ error: Error) {
        lock.lock()
        self.error = error
        lock.unlock()
    }

    func load() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

private struct OfflineSnapshotCachedMetadata: Codable {
    let cacheScopeKey: String?
    let path: String?
    let fileSize: Int64?
    let modifiedAt: Date?
    let contentKind: RemoteComicReferenceKind
    let cachedByteCount: Int64?
}
