import XCTest
@testable import JamReader

final class RemoteServerBrowsingServiceWebDAVTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testListDirectoryClassifiesWebDAVFilesAndImageDirectoryComics() async throws {
        let profile = makeWebDAVProfile()
        let service = makeService()

        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "PROPFIND")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "1")

            let responseBody: String
            switch Self.normalizedDirectoryRequestPath(request.url?.path) {
            case "/dav/comics/":
                responseBody = Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/", displayName: "comics"),
                    Self.directoryResponse(path: "/dav/comics/Image%20Book/", displayName: "Image Book"),
                    Self.directoryResponse(path: "/dav/comics/Series/", displayName: "Series"),
                    Self.fileResponse(path: "/dav/comics/Standalone.cbz", displayName: "Standalone.cbz", size: 123),
                    Self.fileResponse(path: "/dav/comics/Notes.txt", displayName: "Notes.txt", size: 12)
                ])
            case "/dav/comics/Image Book/":
                responseBody = Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/Image%20Book/", displayName: "Image Book"),
                    Self.fileResponse(path: "/dav/comics/Image%20Book/002.png", displayName: "002.png", size: 20),
                    Self.fileResponse(path: "/dav/comics/Image%20Book/001.jpg", displayName: "001.jpg", size: 10),
                    Self.fileResponse(path: "/dav/comics/Image%20Book/ComicInfo.xml", displayName: "ComicInfo.xml", size: 5)
                ])
            case "/dav/comics/Series/":
                responseBody = Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/Series/", displayName: "Series"),
                    Self.fileResponse(path: "/dav/comics/Series/B.cbz", displayName: "B.cbz", size: 200),
                    Self.fileResponse(path: "/dav/comics/Series/A.zip", displayName: "A.zip", size: 100),
                    Self.fileResponse(path: "/dav/comics/Series/C.pdf", displayName: "C.pdf", size: 300),
                    Self.fileResponse(path: "/dav/comics/Series/readme.txt", displayName: "readme.txt", size: 4)
                ])
            default:
                XCTFail("Unexpected WebDAV request path: \(request.url?.path ?? "<nil>")")
                responseBody = Self.multistatus([])
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 207,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/xml"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let items = try await service.listDirectory(for: profile)

        XCTAssertEqual(items.map(\.name), ["Image Book", "Series", "Standalone.cbz", "Notes.txt"])

        let imageBook = try XCTUnwrap(items.first { $0.name == "Image Book" })
        XCTAssertEqual(imageBook.kind, .comicDirectory)
        XCTAssertTrue(imageBook.canOpenAsComic)
        XCTAssertEqual(imageBook.path, "/Image Book")
        XCTAssertEqual(imageBook.pageCountHint, 2)
        XCTAssertEqual(imageBook.coverPath, "/Image Book/001.jpg")
        XCTAssertEqual(imageBook.fileSize, nil)
        XCTAssertTrue(imageBook.previewItems.isEmpty)

        let series = try XCTUnwrap(items.first { $0.name == "Series" })
        XCTAssertEqual(series.kind, .directory)
        XCTAssertEqual(series.path, "/Series")
        XCTAssertEqual(series.previewItems.map(\.name), ["A.zip", "B.cbz"])
        XCTAssertEqual(series.previewItems.map(\.path), ["/Series/A.zip", "/Series/B.cbz"])
        XCTAssertTrue(series.previewItems.allSatisfy(\.canOpenAsComic))

        let standalone = try XCTUnwrap(items.first { $0.name == "Standalone.cbz" })
        XCTAssertEqual(standalone.kind, .comicFile)
        XCTAssertEqual(standalone.path, "/Standalone.cbz")
        XCTAssertEqual(standalone.fileSize, 123)

        let notes = try XCTUnwrap(items.first { $0.name == "Notes.txt" })
        XCTAssertEqual(notes.kind, .unsupportedFile)

        XCTAssertEqual(
            URLProtocolStub.recordedRequests().compactMap { Self.normalizedDirectoryRequestPath($0.url?.path) },
            ["/dav/comics/", "/dav/comics/Image Book/", "/dav/comics/Series/"]
        )
    }

    func testListDirectoryDoesNotTreatMixedContentDirectoryAsImageComic() async throws {
        let profile = makeWebDAVProfile()
        let service = makeService()

        URLProtocolStub.setHandler { request in
            let responseBody: String
            switch Self.normalizedDirectoryRequestPath(request.url?.path) {
            case "/dav/comics/":
                responseBody = Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/", displayName: "comics"),
                    Self.directoryResponse(path: "/dav/comics/Mixed/", displayName: "Mixed")
                ])
            case "/dav/comics/Mixed/":
                responseBody = Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/Mixed/", displayName: "Mixed"),
                    Self.fileResponse(path: "/dav/comics/Mixed/001.jpg", displayName: "001.jpg", size: 10),
                    Self.fileResponse(path: "/dav/comics/Mixed/002.png", displayName: "002.png", size: 10),
                    Self.fileResponse(path: "/dav/comics/Mixed/notes.txt", displayName: "notes.txt", size: 10)
                ])
            default:
                XCTFail("Unexpected WebDAV request path: \(request.url?.path ?? "<nil>")")
                responseBody = Self.multistatus([])
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 207,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/xml"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let items = try await service.listDirectory(for: profile)

        let mixed = try XCTUnwrap(items.first)
        XCTAssertEqual(mixed.name, "Mixed")
        XCTAssertEqual(mixed.kind, .directory)
        XCTAssertFalse(mixed.canOpenAsComic)
        XCTAssertEqual(mixed.pageCountHint, nil)
        XCTAssertTrue(mixed.previewItems.isEmpty)
    }

    func testListDirectoryUsesNormalizedBaseDirectoryPath() async throws {
        var profile = makeWebDAVProfile()
        profile.baseDirectoryPath = "  /Nested//Folder/  "
        let service = makeService()

        URLProtocolStub.setHandler { request in
            XCTAssertEqual(Self.normalizedDirectoryRequestPath(request.url?.path), "/dav/comics/Nested/Folder/")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 207,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/xml"]
                )!,
                Data(Self.multistatus([
                    Self.directoryResponse(path: "/dav/comics/Nested/Folder/", displayName: "Folder"),
                    Self.fileResponse(path: "/dav/comics/Nested/Folder/Book.pdf", displayName: "Book.pdf", size: 4096)
                ]).utf8)
            )
        }

        let items = try await service.listDirectory(for: profile)

        XCTAssertEqual(items.map(\.name), ["Book.pdf"])
        XCTAssertEqual(items.first?.path, "/Nested/Folder/Book.pdf")
        XCTAssertEqual(items.first?.kind, .comicFile)
        XCTAssertEqual(URLProtocolStub.recordedRequests().count, 1)
    }

    private func makeService() -> RemoteServerBrowsingService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return RemoteServerBrowsingService(
            webDAVClient: RemoteWebDAVClient(session: session)
        )
    }

    private func makeWebDAVProfile() -> RemoteServerProfile {
        RemoteServerProfile(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "WebDAV",
            providerKind: .webdav,
            host: "https://dav.example.com",
            port: 443,
            shareName: "/dav/comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private static func multistatus(_ responses: [String]) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
        \(responses.joined(separator: "\n"))
        </d:multistatus>
        """
    }

    private static func normalizedDirectoryRequestPath(_ path: String?) -> String {
        guard let path else {
            return ""
        }

        return path.hasSuffix("/") ? path : path + "/"
    }

    private static func directoryResponse(path: String, displayName: String) -> String {
        response(
            path: path,
            displayName: displayName,
            resourceType: "<d:collection/>",
            contentLength: nil
        )
    }

    private static func fileResponse(path: String, displayName: String, size: Int64) -> String {
        response(
            path: path,
            displayName: displayName,
            resourceType: "",
            contentLength: size
        )
    }

    private static func response(
        path: String,
        displayName: String,
        resourceType: String,
        contentLength: Int64?
    ) -> String {
        let contentLengthNode = contentLength.map { "<d:getcontentlength>\($0)</d:getcontentlength>" } ?? ""
        return """
        <d:response>
          <d:href>\(path)</d:href>
          <d:propstat>
            <d:prop>
              <d:displayname>\(displayName)</d:displayname>
              <d:resourcetype>\(resourceType)</d:resourcetype>
              \(contentLengthNode)
              <d:getlastmodified>Wed, 01 Jan 2025 00:00:00 GMT</d:getlastmodified>
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        """
    }
}
