import XCTest
@testable import JamReader

final class SupportedFormatPolicyTests: XCTestCase {
    func testMOBIIsNotAdvertisedAsAnEBookOrMuPDFDocumentFormat() {
        XCTAssertFalse(EBookDocumentSupport.supportsFileExtension("mobi"))
        XCTAssertFalse(MuPDFDocumentRenderer.supportsFileExtension("mobi"))
    }

    func testRemoteBrowserDoesNotTreatMOBIAsAComicFile() {
        let browsingService = RemoteServerBrowsingService()

        XCTAssertTrue(browsingService.supportsComicFile(named: "book.epub"))
        XCTAssertFalse(browsingService.supportsComicFile(named: "book.mobi"))
    }

    func testComicDocumentLoaderReturnsUnsupportedForExistingMOBIFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let mobiURL = tempDirectory.appendingPathComponent("book.mobi")
        try Data("not a supported reader format".utf8).write(to: mobiURL)

        let document = try ComicDocumentLoader().loadDocument(at: mobiURL)

        guard case .unsupported(let unsupportedDocument) = document else {
            return XCTFail("MOBI should load as an unsupported document.")
        }

        XCTAssertEqual(unsupportedDocument.fileExtension, "mobi")
    }
}
