import XCTest
@testable import JamReader

final class SupportedFormatPolicyTests: XCTestCase {
    func testSupportedComicFormatPolicyContainsCurrentPublicFormats() {
        XCTAssertEqual(
            SupportedComicFormats.archiveFileExtensions,
            Set(["cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt"])
        )
        XCTAssertEqual(SupportedComicFormats.documentFileExtensions, Set(["pdf", "epub"]))
        XCTAssertEqual(
            SupportedComicFormats.comicFileExtensions,
            Set(["cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf", "epub"])
        )
    }

    func testReaderDocumentFormatPoliciesUseSharedSupportedFormatPolicy() {
        XCTAssertEqual(EBookDocumentSupport.supportedExtensions, SupportedComicFormats.eBookFileExtensions)
        XCTAssertEqual(MuPDFDocumentRenderer.supportedExtensions, SupportedComicFormats.muPDFDocumentFileExtensions)
    }

    func testFormatDisplayNamesAreCentralized() {
        XCTAssertEqual(SupportedComicFormats.displayName(forFileExtension: "cbz"), "CBZ (ZIP)")
        XCTAssertEqual(SupportedComicFormats.displayName(forFileExtension: "EPUB"), "EPUB")
        XCTAssertEqual(SupportedComicFormats.displayName(forFileExtension: ""), "Comic File")
        XCTAssertEqual(SupportedComicFormats.displayName(forFileExtension: "unknown"), "UNKNOWN")
    }

    func testMOBIIsNotAdvertisedAsAnEBookOrMuPDFDocumentFormat() {
        XCTAssertFalse(SupportedComicFormats.supportsComicFileExtension("mobi"))
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
