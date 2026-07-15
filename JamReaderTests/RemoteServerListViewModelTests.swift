import XCTest
@testable import JamReader

@MainActor
final class RemoteServerListViewModelTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var suiteNames: [String] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        temporaryDirectories.removeAll()
        suiteNames.removeAll()
        super.tearDown()
    }

    func testClearDownloadsPreservesReadingProgress() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profile = makeProfile()
        let reference = makeReference(profile: profile)
        let progressStore = RemoteReadingProgressStore(
            storage: FileBackedJSONStore(
                fileName: "remote_reading_progress.json",
                storageDirectoryURL: directoryURL
            )
        )
        try progressStore.saveProgress(
            ComicReadingProgress(
                currentPage: 8,
                pageCount: 20,
                hasBeenOpened: true,
                read: false,
                lastTimeOpened: Date(timeIntervalSince1970: 200)
            ),
            for: reference,
            profile: profile
        )

        let viewModel = RemoteServerListViewModel(
            profileStore: RemoteServerProfileStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_servers.json",
                    storageDirectoryURL: directoryURL
                )
            ),
            folderShortcutStore: RemoteFolderShortcutStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_folder_shortcuts.json",
                    storageDirectoryURL: directoryURL
                )
            ),
            credentialStore: RemoteServerCredentialStore(),
            browsingService: RemoteServerBrowsingService(
                cachePolicyStore: RemoteCachePolicyStore(
                    userDefaults: makeUserDefaults()
                )
            ),
            readingProgressStore: progressStore,
            remoteBackgroundImportController: RemoteBackgroundImportController()
        )

        viewModel.clearCache(for: profile)

        let storedProgress = try progressStore.loadProgress(for: reference)
        XCTAssertEqual(storedProgress?.currentPage, 8)
        XCTAssertNil(viewModel.alert)
    }

    func testDeleteIsRejectedWhileAnotherStorageTaskIsRunning() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profile = makeProfile()
        let profileStore = RemoteServerProfileStore(
            storage: FileBackedJSONStore(
                fileName: "remote_servers.json",
                storageDirectoryURL: directoryURL
            )
        )
        try profileStore.save([profile])

        let controller = RemoteBackgroundImportController()
        XCTAssertTrue(controller.beginExclusiveStorageMaintenance())
        defer {
            controller.endExclusiveStorageMaintenance()
        }

        let viewModel = RemoteServerListViewModel(
            profileStore: profileStore,
            folderShortcutStore: RemoteFolderShortcutStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_folder_shortcuts.json",
                    storageDirectoryURL: directoryURL
                )
            ),
            credentialStore: RemoteServerCredentialStore(),
            browsingService: RemoteServerBrowsingService(
                cachePolicyStore: RemoteCachePolicyStore(
                    userDefaults: makeUserDefaults()
                )
            ),
            readingProgressStore: RemoteReadingProgressStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_reading_progress.json",
                    storageDirectoryURL: directoryURL
                )
            ),
            remoteBackgroundImportController: controller
        )
        viewModel.load()

        var draft = viewModel.makeEditDraft(for: profile)
        draft.name = "Renamed Server"
        XCTAssertEqual(viewModel.save(draft: draft)?.title, "Remote Task in Progress")
        XCTAssertEqual(try profileStore.load().first?.name, profile.name)

        XCTAssertFalse(viewModel.delete(profile))
        XCTAssertEqual(viewModel.profiles.map(\.id), [profile.id])
        XCTAssertEqual(try profileStore.load().map(\.id), [profile.id])
        XCTAssertEqual(viewModel.alert?.title, "Remote Task in Progress")
    }

    func testServerDeleteRemovesOfflineRecordsWhenPhysicalCacheCleanupFails() throws {
        let profile = makeProfile()
        let harness = try makeCleanupHarness(profile: profile)

        harness.viewModel.load()

        XCTAssertTrue(harness.viewModel.delete(profile))
        XCTAssertTrue(try harness.offlineCopyStore.loadRecords().isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: harness.serverCacheRootURL.path),
            "The test must exercise the physical-cache failure path."
        )
    }

    func testServerScopeChangeRemovesOfflineRecordsWhenPhysicalCacheCleanupFails() throws {
        let profile = makeProfile()
        let harness = try makeCleanupHarness(profile: profile)

        harness.viewModel.load()
        var draft = harness.viewModel.makeEditDraft(for: profile)
        draft.baseDirectoryPath = "/Updated Library Root"

        XCTAssertNil(harness.viewModel.save(draft: draft))
        XCTAssertTrue(try harness.offlineCopyStore.loadRecords().isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: harness.serverCacheRootURL.path),
            "The test must exercise the physical-cache failure path."
        )
    }

    func testOfflineShelfCountUsesOnlyValidExplicitCopiesAndPreservesFallback() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let storageURL = directoryURL.appendingPathComponent("Storage", isDirectory: true)
        let cachesURL = directoryURL.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cachesURL,
            withIntermediateDirectories: true
        )

        let fileManager = RemoteOfflineCountFileManager(cachesRootURL: cachesURL)
        let profileStorage = FileBackedJSONStore(
            fileName: "remote_servers.json",
            storageDirectoryURL: storageURL
        )
        let profileStore = RemoteServerProfileStore(storage: profileStorage)
        let profile = makeProfile()
        try profileStore.save([profile])

        let offlineCopyStore = RemoteOfflineCopyStore(
            storage: FileBackedJSONStore(
                fileName: "remote_offline_copies.json",
                storageDirectoryURL: storageURL
            )
        )
        _ = try offlineCopyStore.loadRecords { [] }

        let browsingService = RemoteServerBrowsingService(fileManager: fileManager)
        let savedReference = makeReference(
            profile: profile,
            path: "/Series/Saved.cbz",
            fileName: "Saved.cbz"
        )
        let missingReference = makeReference(
            profile: profile,
            path: "/Series/Missing.cbz",
            fileName: "Missing.cbz"
        )
        let automaticCacheReference = makeReference(
            profile: profile,
            path: "/Series/Automatic.cbz",
            fileName: "Automatic.cbz"
        )
        try writeCachedComic(
            for: savedReference,
            browsingService: browsingService,
            fileManager: fileManager
        )
        try writeCachedComic(
            for: automaticCacheReference,
            browsingService: browsingService,
            fileManager: fileManager
        )
        try offlineCopyStore.recordDownloadedCopies(
            for: [savedReference, missingReference]
        )

        let readingProgressStore = RemoteReadingProgressStore(
            storage: FileBackedJSONStore(
                fileName: "remote_reading_progress.json",
                storageDirectoryURL: storageURL
            )
        )
        let snapshotStore = RemoteOfflineLibrarySnapshotStore(
            remoteServerProfileStore: profileStore,
            remoteReadingProgressStore: readingProgressStore,
            remoteOfflineCopyStore: offlineCopyStore,
            remoteServerBrowsingService: browsingService
        )
        let viewModel = RemoteServerListViewModel(
            profileStore: profileStore,
            folderShortcutStore: RemoteFolderShortcutStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_folder_shortcuts.json",
                    storageDirectoryURL: storageURL
                )
            ),
            credentialStore: RemoteServerCredentialStore(),
            browsingService: browsingService,
            readingProgressStore: readingProgressStore,
            remoteOfflineCopyStore: offlineCopyStore,
            remoteOfflineLibrarySnapshotStore: snapshotStore,
            remoteBackgroundImportController: RemoteBackgroundImportController()
        )

        viewModel.load()
        await viewModel.refreshOfflineCopyCounts(forceRefresh: true)?.value

        XCTAssertEqual(viewModel.offlineCopyCount(for: profile), 1)
        XCTAssertEqual(viewModel.totalOfflineCopyCount, 1)
        XCTAssertEqual(viewModel.cacheSummary(for: profile).fileCount, 2)

        try Data("not-json".utf8).write(
            to: profileStorage.storageFileURL(),
            options: .atomic
        )
        await viewModel.refreshOfflineCopyCounts(forceRefresh: true)?.value

        XCTAssertEqual(
            viewModel.offlineCopyCount(for: profile),
            1,
            "A transient snapshot load failure should preserve the last valid count."
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RemoteServerListViewModelTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "RemoteServerListViewModelTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeCleanupHarness(
        profile: RemoteServerProfile
    ) throws -> RemoteServerCleanupHarness {
        let directoryURL = try makeTemporaryDirectory()
        let storageURL = directoryURL.appendingPathComponent("Storage", isDirectory: true)
        let cachesURL = directoryURL.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cachesURL,
            withIntermediateDirectories: true
        )

        let serverCacheRootURL = cachesURL
            .appendingPathComponent("JamReader", isDirectory: true)
            .appendingPathComponent("RemoteComics", isDirectory: true)
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: serverCacheRootURL,
            withIntermediateDirectories: true
        )
        try Data([0, 1, 2, 3]).write(
            to: serverCacheRootURL.appendingPathComponent("cached.cbz")
        )

        let profileStore = RemoteServerProfileStore(
            storage: FileBackedJSONStore(
                fileName: "remote_servers.json",
                storageDirectoryURL: storageURL
            )
        )
        try profileStore.save([profile])

        let offlineCopyStore = RemoteOfflineCopyStore(
            storage: FileBackedJSONStore(
                fileName: "remote_offline_copies.json",
                storageDirectoryURL: storageURL
            )
        )
        try offlineCopyStore.recordDownloadedCopy(
            for: makeReference(profile: profile)
        )

        let browsingService = RemoteServerBrowsingService(
            cachePolicyStore: RemoteCachePolicyStore(
                userDefaults: makeUserDefaults()
            ),
            fileManager: FailingRemoteCacheRemovalFileManager(
                cachesRootURL: cachesURL,
                protectedCacheRootURL: serverCacheRootURL
            )
        )
        let viewModel = RemoteServerListViewModel(
            profileStore: profileStore,
            folderShortcutStore: RemoteFolderShortcutStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_folder_shortcuts.json",
                    storageDirectoryURL: storageURL
                )
            ),
            credentialStore: RemoteServerCredentialStore(),
            browsingService: browsingService,
            readingProgressStore: RemoteReadingProgressStore(
                storage: FileBackedJSONStore(
                    fileName: "remote_reading_progress.json",
                    storageDirectoryURL: storageURL
                )
            ),
            remoteOfflineCopyStore: offlineCopyStore,
            remoteBackgroundImportController: RemoteBackgroundImportController()
        )
        return RemoteServerCleanupHarness(
            viewModel: viewModel,
            offlineCopyStore: offlineCopyStore,
            serverCacheRootURL: serverCacheRootURL
        )
    }

    private func makeProfile() -> RemoteServerProfile {
        RemoteServerProfile(
            id: UUID(),
            name: "Test Server",
            providerKind: .smb,
            host: "example.local",
            port: 445,
            shareName: "Comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeReference(
        profile: RemoteServerProfile,
        path: String = "/Series/book.cbz",
        fileName: String = "book.cbz"
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: profile.id,
            providerKind: profile.providerKind,
            shareName: profile.shareName,
            cacheScopeKey: profile.remoteCacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: 1_024,
            modifiedAt: Date(timeIntervalSince1970: 100),
            contentKind: .file,
            pageCountHint: 20,
            coverPath: nil
        )
    }

    private func writeCachedComic(
        for reference: RemoteComicFileReference,
        browsingService: RemoteServerBrowsingService,
        fileManager: FileManager
    ) throws {
        let cachedFileURL = browsingService.plannedCachedFileURL(for: reference)
        try fileManager.createDirectory(
            at: cachedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            repeating: 0xA5,
            count: Int(reference.fileSize ?? 4)
        ).write(to: cachedFileURL)
    }
}

private struct RemoteServerCleanupHarness {
    let viewModel: RemoteServerListViewModel
    let offlineCopyStore: RemoteOfflineCopyStore
    let serverCacheRootURL: URL
}

private final class FailingRemoteCacheRemovalFileManager: FileManager {
    private let cachesRootURL: URL
    private let protectedCacheRootURL: URL

    init(cachesRootURL: URL, protectedCacheRootURL: URL) {
        self.cachesRootURL = cachesRootURL
        self.protectedCacheRootURL = protectedCacheRootURL.standardizedFileURL
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

    override func removeItem(at URL: URL) throws {
        if URL.standardizedFileURL == protectedCacheRootURL {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

private final class RemoteOfflineCountFileManager: FileManager {
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
