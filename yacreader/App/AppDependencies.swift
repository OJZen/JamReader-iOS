import Foundation

struct AppDependencies {
    let libraryDescriptorStore: LibraryDescriptorStore
    let libraryStorageManager: LibraryStorageManager
    let databaseInspector: SQLiteDatabaseInspector
    let libraryDatabaseReader: LibraryDatabaseReader
    let libraryDatabaseWriter: LibraryDatabaseWriter
    let libraryDatabaseBootstrapper: LibraryDatabaseBootstrapper
    let libraryScanner: LibraryScanner
    let comicDocumentLoader: ComicDocumentLoader
    let libraryCoverLocator: LibraryCoverLocator
    let comicInfoImportService: ComicInfoImportService
    let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore

    static func makeDefault() -> AppDependencies {
        let storageManager = LibraryStorageManager()
        let databaseWriter = LibraryDatabaseWriter()
        return AppDependencies(
            libraryDescriptorStore: LibraryDescriptorStore(),
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
            readerLayoutPreferencesStore: ReaderLayoutPreferencesStore()
        )
    }
}
