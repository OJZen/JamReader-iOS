import Foundation

struct AppDependencies {
    let appLibraryDatabase: AppLibraryDatabase
    let libraryAssetStore: LibraryAssetStore
    let libraryCatalogRepository: LibraryCatalogRepository
    let libraryStateRepository: LibraryStateRepository
    let libraryIndexingService: LibraryIndexingService
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
    let libraryComicRemovalService: LibraryComicRemovalService
    let comicDocumentLoader: ComicDocumentLoader
    let libraryCoverLocator: LibraryCoverLocator
    let comicInfoImportService: ComicInfoImportService
    let remoteServerBrowsingService: RemoteServerBrowsingService
    let remoteReadingProgressStore: RemoteReadingProgressStore
    let remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore
    let remoteBackgroundImportController: RemoteBackgroundImportController
    let remoteBrowserPreferencesStore: RemoteBrowserPreferencesStore
    let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore
    let comicDocumentService: ComicDocumentService
    let comicReaderStateStore: ComicReaderStateStore
    let comicOpenCoordinator: ComicOpenCoordinator

    static func makeDefault() -> AppDependencies {
        let appLibraryDatabase = AppLibraryDatabase()
        let libraryAssetStore = LibraryAssetStore(database: appLibraryDatabase)
        let libraryCatalogRepository = LibraryCatalogRepository(
            database: appLibraryDatabase,
            assetStore: libraryAssetStore
        )
        let libraryStateRepository = LibraryStateRepository(database: appLibraryDatabase)
        let libraryIndexingService = LibraryIndexingService(
            database: appLibraryDatabase,
            assetStore: libraryAssetStore
        )
        let descriptorStore = LibraryDescriptorStore()
        let storageManager = LibraryStorageManager()
        let databaseWriter = LibraryDatabaseWriter()
        let databaseBootstrapper = LibraryDatabaseBootstrapper()
        let libraryScanner = LibraryScanner()
        let libraryMaintenanceStatusStore = LibraryMaintenanceStatusStore()
        let libraryCoverLocator = LibraryCoverLocator()
        let remoteServerCredentialStore = RemoteServerCredentialStore()
        let remoteCachePolicyStore = RemoteCachePolicyStore()
        let remoteReadingProgressStore = RemoteReadingProgressStore()
        let remoteServerProfileStore = RemoteServerProfileStore()
        let remoteFolderShortcutStore = RemoteFolderShortcutStore()
        let remoteBackgroundImportController = RemoteBackgroundImportController()
        let readerLayoutPreferencesStore = ReaderLayoutPreferencesStore()
        let comicDocumentService = ComicDocumentService()
        let comicReaderStateStore = ComicReaderStateStore(
            databaseWriter: databaseWriter,
            remoteReadingProgressStore: remoteReadingProgressStore
        )
        let remoteServerBrowsingService = RemoteServerBrowsingService(
            credentialStore: remoteServerCredentialStore,
            cachePolicyStore: remoteCachePolicyStore
        )
        let comicOpenCoordinator = ComicOpenCoordinator(
            storageManager: storageManager,
            documentService: comicDocumentService,
            remoteServerBrowsingService: remoteServerBrowsingService,
            remoteReadingProgressStore: remoteReadingProgressStore
        )
        return AppDependencies(
            appLibraryDatabase: appLibraryDatabase,
            libraryAssetStore: libraryAssetStore,
            libraryCatalogRepository: libraryCatalogRepository,
            libraryStateRepository: libraryStateRepository,
            libraryIndexingService: libraryIndexingService,
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
            libraryComicRemovalService: LibraryComicRemovalService(
                storageManager: storageManager,
                databaseWriter: databaseWriter,
                coverLocator: libraryCoverLocator
            ),
            comicDocumentLoader: ComicDocumentLoader(),
            libraryCoverLocator: libraryCoverLocator,
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
            readerLayoutPreferencesStore: readerLayoutPreferencesStore,
            comicDocumentService: comicDocumentService,
            comicReaderStateStore: comicReaderStateStore,
            comicOpenCoordinator: comicOpenCoordinator
        )
    }
}
