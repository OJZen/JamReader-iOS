import Foundation

struct AppDependencies {
    let libraryDescriptorStore: LibraryDescriptorStore
    let remoteServerProfileStore: RemoteServerProfileStore
    let remoteFolderShortcutStore: RemoteFolderShortcutStore
    let remoteServerCredentialStore: RemoteServerCredentialStore
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
        let remoteReadingProgressStore = RemoteReadingProgressStore()
        return AppDependencies(
            libraryDescriptorStore: descriptorStore,
            remoteServerProfileStore: RemoteServerProfileStore(),
            remoteFolderShortcutStore: RemoteFolderShortcutStore(),
            remoteServerCredentialStore: remoteServerCredentialStore,
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
            remoteServerBrowsingService: RemoteServerBrowsingService(
                credentialStore: remoteServerCredentialStore
            ),
            remoteReadingProgressStore: remoteReadingProgressStore,
            remoteBrowserPreferencesStore: RemoteBrowserPreferencesStore(),
            readerLayoutPreferencesStore: ReaderLayoutPreferencesStore()
        )
    }
}
