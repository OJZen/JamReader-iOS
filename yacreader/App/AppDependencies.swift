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
    let comicDocumentLoader: ComicDocumentLoader
    let libraryCoverLocator: LibraryCoverLocator
    let comicInfoImportService: ComicInfoImportService
    let remoteServerBrowsingService: RemoteServerBrowsingService
    let remoteReadingProgressStore: RemoteReadingProgressStore
    let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore

    static func makeDefault() -> AppDependencies {
        let storageManager = LibraryStorageManager()
        let databaseWriter = LibraryDatabaseWriter()
        let remoteServerCredentialStore = RemoteServerCredentialStore()
        let remoteReadingProgressStore = RemoteReadingProgressStore()
        return AppDependencies(
            libraryDescriptorStore: LibraryDescriptorStore(),
            remoteServerProfileStore: RemoteServerProfileStore(),
            remoteServerCredentialStore: remoteServerCredentialStore,
            libraryStorageManager: storageManager,
            databaseInspector: SQLiteDatabaseInspector(),
            libraryDatabaseReader: LibraryDatabaseReader(),
            libraryDatabaseWriter: databaseWriter,
            libraryDatabaseBootstrapper: LibraryDatabaseBootstrapper(),
            libraryScanner: LibraryScanner(),
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
