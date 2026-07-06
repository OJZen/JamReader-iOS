import Foundation
@testable import JamReader

final class TestApplicationSupportFileManager: FileManager {
    private let applicationSupportRootURL: URL

    init(applicationSupportRootURL: URL) {
        self.applicationSupportRootURL = applicationSupportRootURL
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory && domain == .userDomainMask {
            if shouldCreate && !fileExists(atPath: applicationSupportRootURL.path) {
                try createDirectory(at: applicationSupportRootURL, withIntermediateDirectories: true)
            }
            return applicationSupportRootURL
        }

        return try super.url(
            for: directory,
            in: domain,
            appropriateFor: url,
            create: shouldCreate
        )
    }
}

struct LibraryDatabaseTestHarness {
    struct RegisteredLibrary {
        let descriptor: LibraryDescriptor
        let sourceRootURL: URL
        let databaseURL: URL
    }

    let rootURL: URL
    let sourceRootURL: URL
    let fileManager: TestApplicationSupportFileManager
    let database: AppLibraryDatabase
    let descriptor: LibraryDescriptor

    var databaseURL: URL {
        get throws {
            try database.contextualDatabaseURL(for: descriptor.id)
        }
    }

    static func make(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JamReaderTests", isDirectory: true)
            .appendingPathComponent(sanitizedTestName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationSupportURL = rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let sourceRootURL = rootURL.appendingPathComponent("SourceLibrary", isDirectory: true)
        let fileManager = TestApplicationSupportFileManager(applicationSupportRootURL: applicationSupportURL)

        try fileManager.createDirectory(at: sourceRootURL, withIntermediateDirectories: true)

        let database = AppLibraryDatabase(fileManager: fileManager)
        let descriptor = LibraryDescriptor(
            id: UUID(),
            kind: .linkedFolder,
            name: "Fixture Library",
            rootPath: sourceRootURL.path,
            bookmarkData: Data(),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        try LibraryDescriptorStore(fileManager: fileManager).save([descriptor])

        return LibraryDatabaseTestHarness(
            rootURL: rootURL,
            sourceRootURL: sourceRootURL,
            fileManager: fileManager,
            database: database,
            descriptor: descriptor
        )
    }

    func remove() {
        try? fileManager.removeItem(at: rootURL)
    }

    func makeScanner() -> LibraryScanner {
        LibraryScanner(fileManager: fileManager)
    }

    func makeReader() -> LibraryDatabaseReader {
        LibraryDatabaseReader(fileManager: fileManager)
    }

    func makeImportedComicsImportService() -> ImportedComicsImportService {
        ImportedComicsImportService(
            store: LibraryDescriptorStore(fileManager: fileManager),
            storageManager: LibraryStorageManager(fileManager: fileManager, database: database),
            databaseBootstrapper: LibraryDatabaseBootstrapper(fileManager: fileManager),
            libraryScanner: makeScanner(),
            maintenanceStatusStore: LibraryMaintenanceStatusStore(fileManager: fileManager),
            directoryImageSequenceInspector: DirectoryImageSequenceInspector(fileManager: fileManager),
            fileManager: fileManager,
            databaseInspector: SQLiteDatabaseInspector(fileManager: fileManager),
            databaseReader: LibraryDatabaseReader(fileManager: fileManager)
        )
    }

    @discardableResult
    func writeFile(_ relativePath: String, bytes: [UInt8] = [0, 1, 2, 3]) throws -> URL {
        let url = sourceRootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: url)
        return url
    }

    @discardableResult
    func createDirectory(_ relativePath: String) throws -> URL {
        let url = sourceRootURL.appendingPathComponent(relativePath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func registerAdditionalLibrary(
        named name: String,
        directoryName: String
    ) throws -> RegisteredLibrary {
        let additionalSourceRootURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: additionalSourceRootURL, withIntermediateDirectories: true)

        let additionalDescriptor = LibraryDescriptor(
            id: UUID(),
            kind: .linkedFolder,
            name: name,
            rootPath: additionalSourceRootURL.path,
            bookmarkData: Data(),
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let store = LibraryDescriptorStore(fileManager: fileManager)
        var descriptors = try store.load()
        descriptors.append(additionalDescriptor)
        try store.save(descriptors)

        return RegisteredLibrary(
            descriptor: additionalDescriptor,
            sourceRootURL: additionalSourceRootURL,
            databaseURL: try database.contextualDatabaseURL(for: additionalDescriptor.id)
        )
    }
}
