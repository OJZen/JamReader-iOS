import Foundation

struct AppDependencies {
    let libraryDescriptorStore: LibraryDescriptorStore
    let remoteServerProfileStore: RemoteServerProfileStore
    let remoteServerCredentialStore: RemoteServerCredentialStore
    let libraryStorageManager: LibraryStorageManager
    let databaseInspector: SQLiteDatabaseInspector
    let libraryDatabaseReader: LibraryDatabaseReader
    let libraryDatabaseWriter: LibraryDatabaseWriter
    let libraryDatabaseBootstrapper: LibraryDatabaseBootstrapper
    let libraryScanner: LibraryScanner
    let importedComicsImportService: ImportedComicsImportService
    let comicDocumentLoader: ComicDocumentLoader
    let libraryCoverLocator: LibraryCoverLocator
    let comicInfoImportService: ComicInfoImportService
    let remoteServerBrowsingService: RemoteServerBrowsingService
    let remoteReadingProgressStore: RemoteReadingProgressStore
    let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore

    static func makeDefault() -> AppDependencies {
        let descriptorStore = LibraryDescriptorStore()
        let storageManager = LibraryStorageManager()
        let databaseWriter = LibraryDatabaseWriter()
        let databaseBootstrapper = LibraryDatabaseBootstrapper()
        let libraryScanner = LibraryScanner()
        let remoteServerCredentialStore = RemoteServerCredentialStore()
        let remoteReadingProgressStore = RemoteReadingProgressStore()
        return AppDependencies(
            libraryDescriptorStore: descriptorStore,
            remoteServerProfileStore: RemoteServerProfileStore(),
            remoteServerCredentialStore: remoteServerCredentialStore,
            libraryStorageManager: storageManager,
            databaseInspector: SQLiteDatabaseInspector(),
            libraryDatabaseReader: LibraryDatabaseReader(),
            libraryDatabaseWriter: databaseWriter,
            libraryDatabaseBootstrapper: databaseBootstrapper,
            libraryScanner: libraryScanner,
            importedComicsImportService: ImportedComicsImportService(
                store: descriptorStore,
                storageManager: storageManager,
                databaseBootstrapper: databaseBootstrapper,
                libraryScanner: libraryScanner
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
            readerLayoutPreferencesStore: ReaderLayoutPreferencesStore()
        )
    }
}
