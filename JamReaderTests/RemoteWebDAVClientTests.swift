import XCTest
@testable import JamReader

final class RemoteWebDAVClientTests: XCTestCase {
    private let directoryURL = URL(string: "https://dav.example.com/dav/root")!

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testListDirectorySendsPropfindRequestAndParsesEntries() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "PROPFIND")
            XCTAssertEqual(Self.normalizedDirectoryRequestPath(request.url?.path), "/dav/root/")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml, text/xml")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic token")

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 207,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/xml"]
                )!,
                Data(Self.multistatus([
                    Self.directoryResponse(path: "/dav/root/", displayName: "root"),
                    Self.directoryResponse(path: "/dav/root/Series/", displayName: "Series"),
                    Self.fileResponse(
                        path: "/dav/root/Book.cbz",
                        displayName: "Book.cbz",
                        size: 4096,
                        modifiedAt: "Wed, 01 Jan 2025 00:00:00 GMT"
                    ),
                    Self.fileResponse(
                        path: "/dav/root/Fallback.pdf",
                        displayName: "",
                        size: 1024,
                        modifiedAt: "invalid-date"
                    )
                ]).utf8)
            )
        }

        let entries = try await makeClient().listDirectory(
            at: directoryURL,
            authorizationHeader: "Basic token"
        )

        XCTAssertEqual(entries.map(\.name), ["root", "Series", "Book.cbz", "Fallback.pdf"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, true, false, false])
        XCTAssertEqual(entries[2].fileSize, 4096)
        XCTAssertEqual(entries[2].modifiedAt?.timeIntervalSince1970, 1_735_689_600)
        XCTAssertEqual(entries[3].fileSize, 1024)
        XCTAssertNil(entries[3].modifiedAt)
    }

    func testListDirectoryRecursivelyUsesDepthInfinity() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "PROPFIND")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "infinity")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 207,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/xml"]
                )!,
                Data(Self.multistatus([
                    Self.directoryResponse(path: "/dav/root/", displayName: "root")
                ]).utf8)
            )
        }

        let entries = try await makeClient().listDirectoryRecursively(
            at: directoryURL,
            authorizationHeader: nil
        )

        XCTAssertEqual(entries.map(\.name), ["root"])
    }

    func testListDirectoryMapsHTTPStatusCodes() async throws {
        try await assertListDirectoryStatusCode(401) { error in
            guard case RemoteWebDAVClientError.authenticationFailed = error else {
                return false
            }
            return true
        }
        try await assertListDirectoryStatusCode(403) { error in
            guard case RemoteWebDAVClientError.accessDenied = error else {
                return false
            }
            return true
        }
        try await assertListDirectoryStatusCode(404) { error in
            guard case RemoteWebDAVClientError.remotePathUnavailable = error else {
                return false
            }
            return true
        }
        try await assertListDirectoryStatusCode(500) { error in
            guard case RemoteWebDAVClientError.unsupportedResponse(500) = error else {
                return false
            }
            return true
        }
    }

    func testDownloadDataSendsGETHeadersAndReturnsPayload() async throws {
        let payload = Data([1, 2, 3])
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic token")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload
            )
        }

        let data = try await makeClient().downloadData(
            from: URL(string: "https://dav.example.com/dav/root/Book.cbz")!,
            authorizationHeader: "Basic token"
        )

        XCTAssertEqual(data, payload)
    }

    func testSupportsRangeRequestsUsesSingleByteRangeProbe() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: nil)!,
                Data([0])
            )
        }

        let supportsRanges = try await makeClient().supportsRangeRequests(
            from: URL(string: "https://dav.example.com/dav/root/Book.cbz")!,
            authorizationHeader: nil
        )

        XCTAssertTrue(supportsRanges)
    }

    func testSupportsRangeRequestsReturnsFalseForFullContentResponse() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data([0])
            )
        }

        let supportsRanges = try await makeClient().supportsRangeRequests(
            from: URL(string: "https://dav.example.com/dav/root/Book.cbz")!,
            authorizationHeader: nil
        )

        XCTAssertFalse(supportsRanges)
    }

    func testAuthorizationHeaderUsesBasicCredentials() {
        XCTAssertEqual(
            RemoteWebDAVClient().authorizationHeader(username: "reader", password: "secret"),
            "Basic cmVhZGVyOnNlY3JldA=="
        )
        XCTAssertNil(RemoteWebDAVClient().authorizationHeader(username: nil, password: "secret"))
        XCTAssertNil(RemoteWebDAVClient().authorizationHeader(username: "reader", password: nil))
    }

    private func makeClient() -> RemoteWebDAVClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return RemoteWebDAVClient(session: URLSession(configuration: configuration))
    }

    private func assertListDirectoryStatusCode(
        _ statusCode: Int,
        matches: @escaping (RemoteWebDAVClientError) -> Bool
    ) async throws {
        URLProtocolStub.reset()
        URLProtocolStub.setHandler { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        do {
            _ = try await makeClient().listDirectory(at: directoryURL, authorizationHeader: nil)
            XCTFail("Expected WebDAV status \(statusCode) to throw.")
        } catch let error as RemoteWebDAVClientError {
            XCTAssertTrue(matches(error), "Unexpected error for status \(statusCode): \(error)")
        } catch {
            XCTFail("Unexpected error for status \(statusCode): \(error)")
        }
    }

    private static func normalizedDirectoryRequestPath(_ path: String?) -> String {
        guard let path else {
            return ""
        }

        return path.hasSuffix("/") ? path : path + "/"
    }

    private static func multistatus(_ responses: [String]) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
        \(responses.joined(separator: "\n"))
        </d:multistatus>
        """
    }

    private static func directoryResponse(path: String, displayName: String) -> String {
        response(
            path: path,
            displayName: displayName,
            resourceType: "<d:collection/>",
            contentLength: nil,
            modifiedAt: nil
        )
    }

    private static func fileResponse(
        path: String,
        displayName: String,
        size: Int64,
        modifiedAt: String
    ) -> String {
        response(
            path: path,
            displayName: displayName,
            resourceType: "",
            contentLength: size,
            modifiedAt: modifiedAt
        )
    }

    private static func response(
        path: String,
        displayName: String,
        resourceType: String,
        contentLength: Int64?,
        modifiedAt: String?
    ) -> String {
        let contentLengthNode = contentLength.map { "<d:getcontentlength>\($0)</d:getcontentlength>" } ?? ""
        let modifiedAtNode = modifiedAt.map { "<d:getlastmodified>\($0)</d:getlastmodified>" } ?? ""
        return """
        <d:response>
          <d:href>\(path)</d:href>
          <d:propstat>
            <d:prop>
              <d:displayname>\(displayName)</d:displayname>
              <d:resourcetype>\(resourceType)</d:resourcetype>
              \(contentLengthNode)
              \(modifiedAtNode)
            </d:prop>
            <d:status>HTTP/1.1 200 OK</d:status>
          </d:propstat>
        </d:response>
        """
    }
}
