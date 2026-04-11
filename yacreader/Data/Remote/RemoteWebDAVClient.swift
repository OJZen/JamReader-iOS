import Foundation

struct RemoteWebDAVDirectoryEntry: Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?
}

enum RemoteWebDAVClientError: LocalizedError {
    case invalidResponse
    case authenticationFailed
    case accessDenied
    case remotePathUnavailable
    case connectionFailed(String)
    case unsupportedResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The WebDAV server returned an invalid response."
        case .authenticationFailed:
            return "The WebDAV server rejected the saved credentials."
        case .accessDenied:
            return "Access to the WebDAV location was denied."
        case .remotePathUnavailable:
            return "The WebDAV path is no longer available."
        case .connectionFailed(let message):
            return message
        case .unsupportedResponse(let statusCode):
            return "The WebDAV server returned HTTP \(statusCode)."
        }
    }
}

final class RemoteWebDAVClient {
    private let session: URLSession
    private let httpDateFormatter: DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        self.httpDateFormatter = formatter
    }

    func listDirectory(
        at directoryURL: URL,
        authorizationHeader: String?
    ) async throws -> [RemoteWebDAVDirectoryEntry] {
        try await listEntries(
            at: directoryURL,
            authorizationHeader: authorizationHeader,
            depth: "1"
        )
    }

    func listDirectoryRecursively(
        at directoryURL: URL,
        authorizationHeader: String?
    ) async throws -> [RemoteWebDAVDirectoryEntry] {
        try await listEntries(
            at: directoryURL,
            authorizationHeader: authorizationHeader,
            depth: "infinity"
        )
    }

    private func listEntries(
        at directoryURL: URL,
        authorizationHeader: String?,
        depth: String
    ) async throws -> [RemoteWebDAVDirectoryEntry] {
        var request = URLRequest(url: ensuredDirectoryURL(directoryURL))
        request.httpMethod = "PROPFIND"
        request.timeoutInterval = 30
        request.httpBody = Self.propfindBody
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml, text/xml", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        let httpResponse = try validatedHTTPResponse(response, allowedStatusCodes: [207])
        guard httpResponse.statusCode == 207 else {
            throw RemoteWebDAVClientError.unsupportedResponse(httpResponse.statusCode)
        }

        let document = XMLHash.config { options in
            options.caseInsensitive = true
            options.shouldProcessNamespaces = true
            options.detectParsingErrors = true
        }.parse(data)

        return document["multistatus"]["response"].all.compactMap { responseNode in
            guard let hrefText = responseNode["href"].element?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  let resolvedURL = URL(string: hrefText, relativeTo: directoryURL)?.absoluteURL else {
                return nil
            }

            let successfulPropstat = responseNode["propstat"].all.first { propstatNode in
                propstatNode["status"].element?.text.contains(" 200 ") == true
            }
            let propNode = successfulPropstat?["prop"] ?? responseNode["prop"]
            let isDirectory = propNode["resourcetype"]["collection"].element != nil
            let displayName = normalizedDisplayName(
                propNode["displayname"].element?.text,
                fallbackURL: resolvedURL,
                isDirectory: isDirectory
            )

            return RemoteWebDAVDirectoryEntry(
                url: resolvedURL,
                name: displayName,
                isDirectory: isDirectory,
                fileSize: Int64(propNode["getcontentlength"].element?.text ?? ""),
                modifiedAt: httpDateFormatter.date(
                    from: propNode["getlastmodified"].element?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
            )
        }
    }

    func download(
        from fileURL: URL,
        authorizationHeader: String?,
        to destinationURL: URL
    ) async throws {
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (temporaryURL, response) = try await session.download(for: request)
        _ = try validatedHTTPResponse(response, allowedStatusCodes: [200, 206])

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    func downloadData(
        from fileURL: URL,
        authorizationHeader: String?
    ) async throws -> Data {
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        _ = try validatedHTTPResponse(response, allowedStatusCodes: [200, 206])
        return data
    }

    func authorizationHeader(username: String?, password: String?) -> String? {
        guard let username, let password else {
            return nil
        }

        let credentialData = Data("\(username):\(password)".utf8)
        return "Basic \(credentialData.base64EncodedString())"
    }

    private func validatedHTTPResponse(
        _ response: URLResponse,
        allowedStatusCodes: Set<Int>
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteWebDAVClientError.invalidResponse
        }

        guard allowedStatusCodes.contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw RemoteWebDAVClientError.authenticationFailed
            case 403:
                throw RemoteWebDAVClientError.accessDenied
            case 404:
                throw RemoteWebDAVClientError.remotePathUnavailable
            default:
                throw RemoteWebDAVClientError.unsupportedResponse(httpResponse.statusCode)
            }
        }

        return httpResponse
    }

    private func normalizedDisplayName(
        _ rawDisplayName: String?,
        fallbackURL: URL,
        isDirectory: Bool
    ) -> String {
        if let rawDisplayName = rawDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawDisplayName.isEmpty {
            return rawDisplayName
        }

        let lastPathComponent = fallbackURL.lastPathComponent.removingPercentEncoding
            ?? fallbackURL.lastPathComponent
        if !lastPathComponent.isEmpty {
            return isDirectory && lastPathComponent == "/" ? "Root" : lastPathComponent
        }

        return isDirectory ? "Folder" : "File"
    }

    private func ensuredDirectoryURL(_ url: URL) -> URL {
        let path = url.path
        guard !path.hasSuffix("/") else {
            return url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = path + "/"
        return components?.url ?? url
    }

    private static let propfindBody = Data(
        """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname />
            <d:resourcetype />
            <d:getcontentlength />
            <d:getlastmodified />
          </d:prop>
        </d:propfind>
        """.utf8
    )
}
