import XCTest
@testable import JamReader

final class ImportedComicsImportServiceIntegrationTests: XCTestCase {
    private var harnesses: [LibraryDatabaseTestHarness] = []

    override func tearDown() {
        for harness in harnesses {
            harness.remove()
        }
        harnesses.removeAll()
        super.tearDown()
    }

    func testImportSingleFileCreatesImportedLibraryCopiesFileAndIndexesIt() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Source.cbz", bytes: [1, 2, 3], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertTrue(result.createdLibrary)
        XCTAssertEqual(result.importedDestinationName, ImportedComicsImportService.defaultImportedComicsLibraryName)
        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertEqual(result.scanSummary?.comicCount, 1)
        XCTAssertEqual(result.unsupportedItemNames, [])
        XCTAssertEqual(result.failedItemNames, [])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        let copiedURL = importedRootURL.appendingPathComponent("Source.cbz")
        XCTAssertTrue(harness.fileManager.fileExists(atPath: copiedURL.path))
        XCTAssertEqual(try Data(contentsOf: copiedURL), Data([1, 2, 3]))

        let comics = try importedComics(for: importedLibrary, harness: harness)
        XCTAssertEqual(comics.map(\.fileName), ["Source.cbz"])
        XCTAssertEqual(comics.compactMap(\.path), ["/Source.cbz"])
    }

    func testImportingSameFileTwiceReusesExistingDestinationWithoutDuplicateCopies() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Repeated.cbz", bytes: [7, 8, 9], harness: harness)
        let service = harness.makeImportedComicsImportService()

        _ = try service.importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )
        let secondResult = try service.importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(secondResult.importedComicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.comicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.reusedComicCount, 1)

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertEqual(
            try regularFileNames(in: importedRootURL, harness: harness),
            ["Repeated.cbz"]
        )
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["Repeated.cbz"]
        )
    }

    func testImportingDifferentFileWithSameNameCreatesUniqueDestinationAndIndexesBoth() throws {
        let harness = try makeHarness()
        let firstSourceDirectory = try createSourceDirectory("First", harness: harness)
        let secondSourceDirectory = try createSourceDirectory("Second", harness: harness)
        let firstURL = try writeFile("Same.cbz", in: firstSourceDirectory, using: harness.fileManager, bytes: [1, 1, 1])
        let secondURL = try writeFile("Same.cbz", in: secondSourceDirectory, using: harness.fileManager, bytes: [2, 2, 2])
        let service = harness.makeImportedComicsImportService()

        _ = try service.importComicResources(
            from: [firstURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )
        let secondResult = try service.importComicResources(
            from: [secondURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(secondResult.importedComicCount, 1)
        XCTAssertEqual(secondResult.scanSummary?.comicCount, 2)

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertEqual(
            try regularFileNames(in: importedRootURL, harness: harness),
            ["Same (1).cbz", "Same.cbz"]
        )
        XCTAssertEqual(
            try importedComics(for: importedLibrary, harness: harness).map(\.fileName),
            ["Same (1).cbz", "Same.cbz"]
        )
    }

    func testDirectoryImportTraversesSupportedFilesAndImageDirectoryComics() throws {
        let harness = try makeHarness()
        let sourceDirectoryURL = try createSourceDirectory("Batch", harness: harness)
        try writeFile("Folder/Issue.cbz", in: sourceDirectoryURL, using: harness.fileManager, bytes: [1])
        try writeFile("Folder/Notes.txt", in: sourceDirectoryURL, using: harness.fileManager, bytes: [2])
        try writeFile("Folder/Image Comic/002.png", in: sourceDirectoryURL, using: harness.fileManager, bytes: [3])
        try writeFile("Folder/Image Comic/001.jpg", in: sourceDirectoryURL, using: harness.fileManager, bytes: [4])

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceDirectoryURL],
            traverseDirectories: true,
            accessSecurityScopedResources: false
        )

        XCTAssertEqual(result.importedComicCount, 2)
        XCTAssertEqual(result.scanSummary?.comicCount, 2)
        XCTAssertEqual(result.unsupportedItemNames, [])
        XCTAssertEqual(result.failedItemNames, [])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let comics = try importedComics(for: importedLibrary, harness: harness)
        XCTAssertEqual(comics.map(\.fileName), ["Image Comic", "Issue.cbz"])
        XCTAssertEqual(
            comics.compactMap(\.path).sorted(),
            ["/Image Comic", "/Issue.cbz"]
        )
        XCTAssertEqual(comics.first { $0.fileName == "Image Comic" }?.pageCount, 2)
    }

    func testImportIntoSelectedLibraryCopiesAndIndexesWithinThatLibraryOnly() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("Selected.cbz", bytes: [5, 6, 7], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            destinationSelection: .library(harness.descriptor.id)
        )

        XCTAssertFalse(result.createdLibrary)
        XCTAssertEqual(result.importedDestinationID, harness.descriptor.id)
        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertEqual(result.scanSummary?.comicCount, 1)
        XCTAssertEqual(
            try harness.makeReader().loadAllComics(databaseURL: harness.databaseURL).map(\.fileName),
            ["Selected.cbz"]
        )
        XCTAssertEqual(try LibraryDescriptorStore(fileManager: harness.fileManager).load().map(\.kind), [.linkedFolder])
    }

    func testConsumeSourceURLsMovesImportedFileIntoDestination() throws {
        let harness = try makeHarness()
        let sourceURL = try writeSourceFile("MoveMe.cbz", bytes: [8, 9, 10], harness: harness)

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false,
            consumeSourceURLs: [sourceURL.standardizedFileURL]
        )

        XCTAssertEqual(result.importedComicCount, 1)
        XCTAssertFalse(harness.fileManager.fileExists(atPath: sourceURL.path))

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        let importedRootURL = try importedRootURL(for: importedLibrary, harness: harness)
        XCTAssertTrue(harness.fileManager.fileExists(atPath: importedRootURL.appendingPathComponent("MoveMe.cbz").path))
    }

    func testNonTraversedNonComicDirectoryIsReportedUnsupported() throws {
        let harness = try makeHarness()
        let sourceDirectoryURL = try createSourceDirectory("Plain Folder", harness: harness)
        try writeFile("Readme.txt", in: sourceDirectoryURL, using: harness.fileManager, bytes: [1])

        let result = try harness.makeImportedComicsImportService().importComicResources(
            from: [sourceDirectoryURL],
            traverseDirectories: false,
            accessSecurityScopedResources: false
        )

        XCTAssertTrue(result.createdLibrary)
        XCTAssertEqual(result.importedComicCount, 0)
        XCTAssertNil(result.scanSummary)
        XCTAssertEqual(result.unsupportedItemNames, ["Plain Folder"])

        let importedLibrary = try importedLibraryDescriptor(harness: harness)
        XCTAssertEqual(try importedComics(for: importedLibrary, harness: harness), [])
    }

    private func makeHarness(testName: String = #function) throws -> LibraryDatabaseTestHarness {
        let harness = try LibraryDatabaseTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }

    private func importedLibraryDescriptor(harness: LibraryDatabaseTestHarness) throws -> LibraryDescriptor {
        let descriptors = try LibraryDescriptorStore(fileManager: harness.fileManager).load()
        return try XCTUnwrap(descriptors.first { $0.kind == .importedComics })
    }

    private func importedRootURL(
        for descriptor: LibraryDescriptor,
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        try LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
            .restoreSourceURL(for: descriptor)
            .standardizedFileURL
    }

    private func importedComics(
        for descriptor: LibraryDescriptor,
        harness: LibraryDatabaseTestHarness
    ) throws -> [LibraryComic] {
        let storageManager = LibraryStorageManager(fileManager: harness.fileManager, database: harness.database)
        return try LibraryDatabaseReader(fileManager: harness.fileManager)
            .loadAllComics(databaseURL: storageManager.databaseURL(for: descriptor))
    }

    private func regularFileNames(
        in directoryURL: URL,
        harness: LibraryDatabaseTestHarness
    ) throws -> [String] {
        try harness.fileManager
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    private func writeSourceFile(
        _ relativePath: String,
        bytes: [UInt8],
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        let sourceDirectoryURL = try createSourceDirectory("ImportSources", harness: harness)
        return try writeFile(relativePath, in: sourceDirectoryURL, using: harness.fileManager, bytes: bytes)
    }

    private func createSourceDirectory(
        _ relativePath: String,
        harness: LibraryDatabaseTestHarness
    ) throws -> URL {
        let url = harness.rootURL
            .appendingPathComponent("ExternalSources", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
        try harness.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeFile(
        _ relativePath: String,
        in sourceRootURL: URL,
        using fileManager: FileManager,
        bytes: [UInt8]
    ) throws -> URL {
        let url = sourceRootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: url)
        return url
    }
}
