import Foundation

struct AppDependencies {
    let libraryDescriptorStore: LibraryDescriptorStore
    let remoteServerProfileStore: RemoteServerProfileStore
    let remoteFolderShortcutStore: RemoteFolderShortcutStore
    let remoteFolderShortcutSnapshotStore: RemoteFolderShortcutSnapshotStore
    let remoteServerCredentialStore: RemoteServerCredentialStore
    let remoteCachePolicyStore: RemoteCachePolicyStore
    let libraryStorageManager: LibraryStorageManager
    let databaseInspector: SQLiteDatabaseInspector
    let libraryDatabaseReader: LibraryDatabaseReader
    let libraryDatabaseWriter: LibraryDatabaseWriter
    let libraryDatabaseBootstrapper: LibraryDatabaseBootstrapper
    let libraryScanner: LibraryScanner
    let libraryMaintenanceStatusStore: LibraryMaintenanceStatusStore
    let importedComicsImportService: ImportedComicsImportService
    let comicDocumentLoader: ComicDocumentLoader
    let libraryCoverLocator: LibraryCoverLocator
    let comicInfoImportService: ComicInfoImportService
    let remoteServerBrowsingService: RemoteServerBrowsingService
    let remoteReadingProgressStore: RemoteReadingProgressStore
    let remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore
    let remoteBackgroundImportController: RemoteBackgroundImportController
    let remoteBrowserPreferencesStore: RemoteBrowserPreferencesStore
    let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore

    static func makeDefault() -> AppDependencies {
        let descriptorStore = LibraryDescriptorStore()
        let storageManager = LibraryStorageManager()
        let databaseWriter = LibraryDatabaseWriter()
        let databaseBootstrapper = LibraryDatabaseBootstrapper()
        let libraryScanner = LibraryScanner()
        let libraryMaintenanceStatusStore = LibraryMaintenanceStatusStore()
        let remoteServerCredentialStore = RemoteServerCredentialStore()
        let remoteCachePolicyStore = RemoteCachePolicyStore()
        let remoteReadingProgressStore = RemoteReadingProgressStore()
        let remoteServerProfileStore = RemoteServerProfileStore()
        let remoteFolderShortcutStore = RemoteFolderShortcutStore()
        let remoteBackgroundImportController = RemoteBackgroundImportController()
        let remoteServerBrowsingService = RemoteServerBrowsingService(
            credentialStore: remoteServerCredentialStore,
            cachePolicyStore: remoteCachePolicyStore
        )
        return AppDependencies(
            libraryDescriptorStore: descriptorStore,
            remoteServerProfileStore: remoteServerProfileStore,
            remoteFolderShortcutStore: remoteFolderShortcutStore,
            remoteFolderShortcutSnapshotStore: RemoteFolderShortcutSnapshotStore(
                remoteServerProfileStore: remoteServerProfileStore,
                remoteFolderShortcutStore: remoteFolderShortcutStore
            ),
            remoteServerCredentialStore: remoteServerCredentialStore,
            remoteCachePolicyStore: remoteCachePolicyStore,
            libraryStorageManager: storageManager,
            databaseInspector: SQLiteDatabaseInspector(),
            libraryDatabaseReader: LibraryDatabaseReader(),
            libraryDatabaseWriter: databaseWriter,
            libraryDatabaseBootstrapper: databaseBootstrapper,
            libraryScanner: libraryScanner,
            libraryMaintenanceStatusStore: libraryMaintenanceStatusStore,
            importedComicsImportService: ImportedComicsImportService(
                store: descriptorStore,
                storageManager: storageManager,
                databaseBootstrapper: databaseBootstrapper,
                libraryScanner: libraryScanner,
                maintenanceStatusStore: libraryMaintenanceStatusStore
            ),
            comicDocumentLoader: ComicDocumentLoader(),
            libraryCoverLocator: LibraryCoverLocator(),
            comicInfoImportService: ComicInfoImportService(
                storageManager: storageManager,
                databaseWriter: databaseWriter
            ),
            remoteServerBrowsingService: remoteServerBrowsingService,
            remoteReadingProgressStore: remoteReadingProgressStore,
            remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore(
                remoteServerProfileStore: remoteServerProfileStore,
                remoteReadingProgressStore: remoteReadingProgressStore,
                remoteServerBrowsingService: remoteServerBrowsingService
            ),
            remoteBackgroundImportController: remoteBackgroundImportController,
            remoteBrowserPreferencesStore: RemoteBrowserPreferencesStore(),
            readerLayoutPreferencesStore: ReaderLayoutPreferencesStore()
        )
    }
}
