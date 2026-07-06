import XCTest
@testable import JamReader

final class DirectoryImageSequenceInspectorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testImageDominantFlatDirectoryIsRecognizedAsComicDirectory() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("10.jpg", in: directoryURL)
        try writeFile("2.png", in: directoryURL)
        try writeFile("001.webp", in: directoryURL)
        try writeFile("ComicInfo.xml", in: directoryURL)
        try writeFile("Thumbs.db", in: directoryURL)

        let inspection = try XCTUnwrap(
            DirectoryImageSequenceInspector().inspectComicDirectory(at: directoryURL)
        )

        XCTAssertEqual(inspection.pageFiles.map(\.lastPathComponent), ["001.webp", "2.png", "10.jpg"])
        XCTAssertEqual(inspection.comicInfoURL?.lastPathComponent, "ComicInfo.xml")
    }

    func testDirectoryWithNestedDirectoryIsNotTreatedAsSingleComic() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("001.jpg", in: directoryURL)
        try writeFile("002.jpg", in: directoryURL)
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("Chapter 2", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertNil(try DirectoryImageSequenceInspector().inspectComicDirectory(at: directoryURL))
    }

    func testDirectoryWithTooManyNonImageFilesIsNotTreatedAsComic() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("001.jpg", in: directoryURL)
        try writeFile("002.jpg", in: directoryURL)
        try writeFile("notes.txt", in: directoryURL)
        try writeFile("metadata.json", in: directoryURL)

        XCTAssertNil(try DirectoryImageSequenceInspector().inspectComicDirectory(at: directoryURL))
    }

    func testFingerprintIsStableForSameDirectoryContent() throws {
        let directoryURL = try makeTemporaryDirectory()
        try writeFile("001.jpg", in: directoryURL, bytes: [1, 2, 3])
        try writeFile("002.jpg", in: directoryURL, bytes: [4, 5, 6, 7])

        let inspector = DirectoryImageSequenceInspector()
        let firstInspection = try XCTUnwrap(inspector.inspectComicDirectory(at: directoryURL))
        let secondInspection = try XCTUnwrap(inspector.inspectComicDirectory(at: directoryURL))

        XCTAssertEqual(
            try inspector.fingerprint(for: firstInspection),
            try inspector.fingerprint(for: secondInspection)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectoryImageSequenceInspectorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func writeFile(
        _ name: String,
        in directoryURL: URL,
        bytes: [UInt8] = [0, 1, 2, 3]
    ) throws {
        try Data(bytes).write(to: directoryURL.appendingPathComponent(name))
    }
}
