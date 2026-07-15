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
        profile: RemoteServerProfile
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: profile.id,
            providerKind: profile.providerKind,
            shareName: profile.shareName,
            cacheScopeKey: profile.remoteCacheScopeKey,
            path: "/Series/book.cbz",
            fileName: "book.cbz",
            fileSize: 1_024,
            modifiedAt: Date(timeIntervalSince1970: 100),
            contentKind: .file,
            pageCountHint: 20,
            coverPath: nil
        )
    }
}
