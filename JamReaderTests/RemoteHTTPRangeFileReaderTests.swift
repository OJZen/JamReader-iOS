import XCTest
@testable import JamReader

final class RemoteHTTPRangeFileReaderTests: XCTestCase {
    private let testURL = URL(string: "https://example.com/comics/book.cbz")!

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testFileSizeUsesHEADContentLengthAndCachesResult() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "4096"]
                )!,
                Data()
            )
        }

        let reader = RemoteHTTPRangeFileReader(url: testURL, session: makeSession())

        let firstFileSize = try await reader.fileSize
        let cachedFileSize = try await reader.fileSize
        XCTAssertEqual(firstFileSize, 4096)
        XCTAssertEqual(cachedFileSize, 4096)
        XCTAssertEqual(URLProtocolStub.recordedRequests().count, 1)
    }

    func testFileSizeFallsBackToRangeProbeWhenHEADDoesNotReturnContentLength() async throws {
        URLProtocolStub.setHandler { request in
            if request.httpMethod == "HEAD" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [:]
                    )!,
                    Data()
                )
            }

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-0")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Range": "bytes 0-0/12345"]
                )!,
                Data([0])
            )
        }

        let reader = RemoteHTTPRangeFileReader(url: testURL, session: makeSession())

        let fileSize = try await reader.fileSize
        XCTAssertEqual(fileSize, 12_345)
        XCTAssertEqual(URLProtocolStub.recordedRequests().map(\.httpMethod), ["HEAD", "GET"])
    }

    func testReadRequestsExactRangeAndAuthorizationHeader() async throws {
        let payload = Data([1, 2, 3, 4])
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=10-13")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 206,
                    httpVersion: nil,
                    headerFields: ["Content-Range": "bytes 10-13/100"]
                )!,
                payload
            )
        }

        let reader = RemoteHTTPRangeFileReader(
            url: testURL,
            session: makeSession(),
            authorizationHeader: "Basic token"
        )

        let readData = try await reader.read(offset: 10, length: 4)
        XCTAssertEqual(readData, payload)
    }

    func testReadWithZeroLengthDoesNotIssueRequest() async throws {
        URLProtocolStub.setHandler { _ in
            XCTFail("Zero-length reads should not hit the network.")
            return (
                HTTPURLResponse(url: self.testURL, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let reader = RemoteHTTPRangeFileReader(url: testURL, session: makeSession())

        let readData = try await reader.read(offset: 10, length: 0)
        XCTAssertEqual(readData, Data())
        XCTAssertEqual(URLProtocolStub.recordedRequests().count, 0)
    }

    func testReadMarksServerWithoutRangeSupportAndAvoidsSecondRequest() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "100"]
                )!,
                Data(repeating: 0, count: 100)
            )
        }

        let reader = RemoteHTTPRangeFileReader(url: testURL, session: makeSession())

        do {
            _ = try await reader.read(offset: 0, length: 4)
            XCTFail("Expected a range support error.")
        } catch RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await reader.read(offset: 4, length: 4)
            XCTFail("Expected cached range support error.")
        } catch RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(URLProtocolStub.recordedRequests().count, 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
