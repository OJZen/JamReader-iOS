import Foundation

enum RemoteHTTPRangeFileReaderError: LocalizedError {
    case invalidResponse
    case missingContentLength
    case unreadableRange
    case rangeRequestsUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The remote file response was not valid."
        case .missingContentLength:
            return "The remote file size could not be determined."
        case .unreadableRange:
            return "The requested remote byte range could not be read."
        case .rangeRequestsUnsupported:
            return "This WebDAV server does not support byte-range reads for direct thumbnails."
        }
    }
}

final class RemoteHTTPRangeFileReader: RemoteRandomAccessFileReader {
    private let url: URL
    private let session: URLSession
    private let authorizationHeader: String?
    private let fileSizeCache = RemoteHTTPRangeFileSizeCache()
    private let rangeSupportCache = RemoteHTTPRangeSupportCache()

    init(
        url: URL,
        session: URLSession = .shared,
        authorizationHeader: String? = nil
    ) {
        self.url = url
        self.session = session
        self.authorizationHeader = authorizationHeader
    }

    var fileSize: UInt64 {
        get async throws {
            if let cachedFileSize = await fileSizeCache.value {
                return cachedFileSize
            }

            let resolvedSize = try await resolveFileSize()
            await fileSizeCache.store(resolvedSize)
            return resolvedSize
        }
    }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        guard length > 0 else {
            return Data()
        }

        try Task.checkCancellation()

        if let supportsRangeRequests = await rangeSupportCache.value,
           supportsRangeRequests == false {
            throw RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(
            "bytes=\(offset)-\(offset + UInt64(length) - 1)",
            forHTTPHeaderField: "Range"
        )
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteHTTPRangeFileReaderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 206:
            await rangeSupportCache.store(true)
            return data
        case 200:
            await rangeSupportCache.store(false)
            throw RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported
        default:
            throw RemoteHTTPRangeFileReaderError.unreadableRange
        }
    }

    func close() async throws {
    }

    private func resolveFileSize() async throws -> UInt64 {
        try Task.checkCancellation()

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 15
        headRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let authorizationHeader {
            headRequest.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: headRequest)
            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode),
               let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let resolvedSize = UInt64(contentLength) {
                return resolvedSize
            }
        } catch {
        }

        var rangeRequest = URLRequest(url: url)
        rangeRequest.httpMethod = "GET"
        rangeRequest.timeoutInterval = 30
        rangeRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        if let authorizationHeader {
            rangeRequest.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await session.data(for: rangeRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteHTTPRangeFileReaderError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 206:
            await rangeSupportCache.store(true)
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let totalLength = contentRange.split(separator: "/").last,
               let resolvedSize = UInt64(totalLength) {
                return resolvedSize
            }
        case 200:
            await rangeSupportCache.store(false)
        default:
            break
        }

        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let resolvedSize = UInt64(contentLength) {
            return resolvedSize
        }

        throw RemoteHTTPRangeFileReaderError.missingContentLength
    }
}

private actor RemoteHTTPRangeFileSizeCache {
    private(set) var value: UInt64?

    func store(_ value: UInt64) {
        self.value = value
    }
}

private actor RemoteHTTPRangeSupportCache {
    private(set) var value: Bool?

    func store(_ value: Bool) {
        self.value = value
    }
}
