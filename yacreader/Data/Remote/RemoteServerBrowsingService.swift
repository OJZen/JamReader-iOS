import Foundation

enum RemoteServerBrowsingError: LocalizedError {
    case invalidProfile(String)
    case providerIntegrationUnavailable(RemoteProviderKind)
    case unsupportedComicFile(String)
    case missingCredentials(String)
    case authenticationFailed(String)
    case shareUnavailable(String)
    case remotePathUnavailable(String)
    case accessDenied(String)
    case connectionFailed(String)
    case cacheMaintenanceFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason):
            return reason
        case .providerIntegrationUnavailable(let providerKind):
            return "\(providerKind.title) browsing is planned but not wired into a live network client yet."
        case .unsupportedComicFile(let fileName):
            return "\(fileName) is not a supported remote comic file."
        case .missingCredentials(let reason):
            return reason
        case .authenticationFailed(let serverName):
            return "Could not sign in to \(serverName). Check the username and password, then try again."
        case .shareUnavailable(let shareName):
            return "The SMB share \(shareName) is not available right now."
        case .remotePathUnavailable(let path):
            return "\(path) is no longer available on the remote server."
        case .accessDenied(let location):
            return "Access was denied for \(location)."
        case .connectionFailed(let endpoint):
            return "Could not reach \(endpoint). Check that the server is online and reachable from this device."
        case .cacheMaintenanceFailed(let reason):
            return reason
        case .operationFailed(let reason):
            return reason
        }
    }
}

struct RemoteServerValidationIssue: Identifiable, Hashable {
    enum Severity: String, Hashable {
        case error
        case warning
    }

    let id = UUID()
    let severity: Severity
    let message: String
}

struct RemoteServerBrowserCapabilities: Hashable {
    let providerKind: RemoteProviderKind
    let supportsDirectoryBrowsing: Bool
    let supportsSingleComicOpening: Bool
    let plannedClientLibrary: String
}

struct RemoteComicDownloadResult: Hashable {
    enum Source: Hashable {
        case downloaded
        case cachedCurrent
        case cachedFallback(String)
    }

    let localFileURL: URL
    let source: Source
}

struct RemoteComicCacheSummary: Hashable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = RemoteComicCacheSummary(fileCount: 0, totalBytes: 0)

    var isEmpty: Bool {
        fileCount == 0 || totalBytes <= 0
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var summaryText: String {
        if fileCount == 1 {
            return "1 cached comic · \(sizeText)"
        }

        return "\(fileCount) cached comics · \(sizeText)"
    }
}

final class RemoteServerBrowsingService {
    private let supportedComicFileExtensions: Set<String> = [
        "cbz", "zip", "cbr", "rar", "cb7", "7z", "cbt", "tar", "pdf"
    ]
    private let maximumCachedComicFileCount = 48
    private let maximumTotalCacheBytes: Int64 = 2 * 1024 * 1024 * 1024
    private let credentialStore: RemoteServerCredentialStore
    private let fileManager: FileManager
    private let remoteComicCacheRootURL: URL

    init(
        credentialStore: RemoteServerCredentialStore = RemoteServerCredentialStore(),
        fileManager: FileManager = .default
    ) {
        self.credentialStore = credentialStore
        self.fileManager = fileManager
        self.remoteComicCacheRootURL = (
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("RemoteComics", isDirectory: true)
    }

    func capabilities(for providerKind: RemoteProviderKind) -> RemoteServerBrowserCapabilities {
        switch providerKind {
        case .smb:
            return RemoteServerBrowserCapabilities(
                providerKind: .smb,
                supportsDirectoryBrowsing: true,
                supportsSingleComicOpening: true,
                plannedClientLibrary: "SMBClient 0.3.1"
            )
        }
    }

    func validateProfile(_ profile: RemoteServerProfile) -> [RemoteServerValidationIssue] {
        var issues: [RemoteServerValidationIssue] = []

        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "A display name is required for the remote server."
                )
            )
        }

        if profile.normalizedHost.isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Host cannot be empty."
                )
            )
        }

        if profile.port <= 0 || profile.port > 65535 {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Port must be between 1 and 65535."
                )
            )
        }

        if profile.normalizedShareName.isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Share name cannot be empty."
                )
            )
        }

        if profile.authenticationMode.requiresUsername
            && profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "Username is required for this authentication mode."
                )
            )
        }

        if profile.authenticationMode.requiresPassword && profile.passwordReferenceKey == nil {
            issues.append(
                RemoteServerValidationIssue(
                    severity: .error,
                    message: "A saved password is required for this SMB server."
                )
            )
        }

        return issues
    }

    func listDirectory(
        for profile: RemoteServerProfile,
        path: String? = nil
    ) async throws -> [RemoteDirectoryItem] {
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The SMB server profile is incomplete.")
        }

        let requestedPath = normalizeDisplayPath(path ?? profile.normalizedBaseDirectoryPath)
        return try await withConnectedClient(for: profile) { client in
            let shareRelativePath = shareRelativePath(forDisplayPath: requestedPath)
            let entries = try await client.listDirectory(path: shareRelativePath)

            return entries.compactMap { entry in
                guard !isSkippableDirectoryEntry(entry.name) else {
                    return nil
                }

                let fullPath = appendPathComponent(entry.name, to: requestedPath)
                return classifyDirectoryEntry(
                    named: entry.name,
                    fullPath: fullPath,
                    isDirectory: entry.isDirectory,
                    in: profile,
                    fileSize: Int64(clamping: entry.size),
                    modifiedAt: entry.lastWriteTime
                )
            }
        }
    }

    func listComicFilesRecursively(
        for profile: RemoteServerProfile,
        path: String? = nil
    ) async throws -> [RemoteDirectoryItem] {
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The SMB server profile is incomplete.")
        }

        let requestedPath = normalizeDisplayPath(path ?? profile.normalizedBaseDirectoryPath)
        return try await withConnectedClient(for: profile) { client in
            try await recursivelyListComicFiles(
                with: client,
                for: profile,
                displayPath: requestedPath
            )
        }
    }

    func downloadComicFile(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        forceRefresh: Bool = false
    ) async throws -> RemoteComicDownloadResult {
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The SMB server profile is incomplete.")
        }

        let destinationURL = cachedFileURL(for: reference)
        if !forceRefresh, isCachedComicCurrent(at: destinationURL, reference: reference) {
            touchCachedFile(at: destinationURL)
            return RemoteComicDownloadResult(localFileURL: destinationURL, source: .cachedCurrent)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryDownloadURL = destinationURL.appendingPathExtension("download")
        try? fileManager.removeItem(at: temporaryDownloadURL)

        do {
            try await withConnectedClient(for: profile) { client in
                try await client.download(
                    path: shareRelativePath(forDisplayPath: reference.path),
                    localPath: temporaryDownloadURL,
                    overwrite: true
                )
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryDownloadURL, to: destinationURL)
            touchCachedFile(at: destinationURL)
            try? trimCacheIfNeeded()
            return RemoteComicDownloadResult(localFileURL: destinationURL, source: .downloaded)
        } catch {
            try? fileManager.removeItem(at: temporaryDownloadURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                touchCachedFile(at: destinationURL)
                return RemoteComicDownloadResult(
                    localFileURL: destinationURL,
                    source: .cachedFallback(cachedFallbackMessage(for: error, profile: profile))
                )
            }

            throw normalizeBrowsingError(
                error,
                profile: profile,
                remotePath: reference.path
            )
        }
    }

    func cacheSummary(for profile: RemoteServerProfile? = nil) -> RemoteComicCacheSummary {
        let cacheURL = cacheRootURL(for: profile)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return .empty
        }

        guard let enumerator = fileManager.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }

        var fileCount = 0
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues?.isRegularFile == true else {
                continue
            }

            fileCount += 1
            totalBytes += Int64(resourceValues?.fileSize ?? 0)
        }

        return RemoteComicCacheSummary(fileCount: fileCount, totalBytes: totalBytes)
    }

    func clearCachedComics(for profile: RemoteServerProfile? = nil) throws {
        let cacheURL = cacheRootURL(for: profile)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: cacheURL)
        } catch {
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The downloaded remote comic cache could not be cleared. \(error.localizedDescription)"
            )
        }
    }

    func classifyDirectoryEntry(
        named name: String,
        fullPath: String,
        isDirectory: Bool,
        in profile: RemoteServerProfile,
        fileSize: Int64? = nil,
        modifiedAt: Date? = nil
    ) -> RemoteDirectoryItem {
        let kind: RemoteDirectoryItemKind
        if isDirectory {
            kind = .directory
        } else if supportsComicFile(named: name) {
            kind = .comicFile
        } else {
            kind = .unsupportedFile
        }

        return RemoteDirectoryItem(
            serverID: profile.id,
            providerKind: profile.providerKind,
            shareName: profile.normalizedShareName,
            path: fullPath,
            name: name,
            kind: kind,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    func makeComicFileReference(
        from item: RemoteDirectoryItem
    ) throws -> RemoteComicFileReference {
        guard item.canOpenAsComic else {
            throw RemoteServerBrowsingError.unsupportedComicFile(item.name)
        }

        return RemoteComicFileReference(
            serverID: item.serverID,
            providerKind: item.providerKind,
            shareName: item.shareName,
            path: item.path,
            fileName: item.name,
            fileSize: item.fileSize,
            modifiedAt: item.modifiedAt
        )
    }

    func supportsComicFile(named fileName: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return supportedComicFileExtensions.contains(fileExtension)
    }

    private func withConnectedClient<T>(
        for profile: RemoteServerProfile,
        operation: (SMBClient) async throws -> T
    ) async throws -> T {
        let client = SMBClient(host: profile.normalizedHost, port: profile.port)
        let credentials = try resolvedCredentials(for: profile)

        do {
            try await client.login(
                username: credentials.username,
                password: credentials.password
            )
            try await client.connectShare(profile.normalizedShareName)

            defer {
                client.session.disconnect()
            }

            return try await operation(client)
        } catch {
            client.session.disconnect()
            throw normalizeBrowsingError(
                error,
                profile: profile,
                remotePath: profile.connectionDisplayPath
            )
        }
    }

    private func recursivelyListComicFiles(
        with client: SMBClient,
        for profile: RemoteServerProfile,
        displayPath: String
    ) async throws -> [RemoteDirectoryItem] {
        let shareRelativePath = shareRelativePath(forDisplayPath: displayPath)

        let entries: [File]
        do {
            entries = try await client.listDirectory(path: shareRelativePath)
        } catch {
            throw normalizeBrowsingError(
                error,
                profile: profile,
                remotePath: displayPath.isEmpty ? profile.connectionDisplayPath : displayPath
            )
        }

        var comicFiles: [RemoteDirectoryItem] = []

        for entry in entries {
            guard !isSkippableDirectoryEntry(entry.name) else {
                continue
            }

            let fullPath = appendPathComponent(entry.name, to: displayPath)
            if entry.isDirectory {
                let nestedComicFiles = try await recursivelyListComicFiles(
                    with: client,
                    for: profile,
                    displayPath: fullPath
                )
                comicFiles.append(contentsOf: nestedComicFiles)
                continue
            }

            guard supportsComicFile(named: entry.name) else {
                continue
            }

            comicFiles.append(
                classifyDirectoryEntry(
                    named: entry.name,
                    fullPath: fullPath,
                    isDirectory: false,
                    in: profile,
                    fileSize: Int64(clamping: entry.size),
                    modifiedAt: entry.lastWriteTime
                )
            )
        }

        return comicFiles
    }

    private func resolvedCredentials(
        for profile: RemoteServerProfile
    ) throws -> (username: String?, password: String?) {
        switch profile.authenticationMode {
        case .guest:
            return (nil, nil)
        case .usernamePassword:
            guard let passwordReferenceKey = profile.passwordReferenceKey else {
                throw RemoteServerBrowsingError.missingCredentials(
                    "This SMB server needs a stored password before it can connect."
                )
            }

            guard let password = try credentialStore.loadPassword(for: passwordReferenceKey) else {
                throw RemoteServerBrowsingError.missingCredentials(
                    "The saved password for this SMB server is missing. Edit the server and save the password again."
                )
            }

            return (profile.username, password)
        }
    }

    private func normalizeDisplayPath(_ rawPath: String) -> String {
        let collapsedPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !collapsedPath.isEmpty else {
            return ""
        }

        return "/" + collapsedPath
    }

    private func shareRelativePath(forDisplayPath path: String) -> String {
        let normalizedPath = normalizeDisplayPath(path)
        guard !normalizedPath.isEmpty else {
            return ""
        }

        return String(normalizedPath.dropFirst())
    }

    private func appendPathComponent(_ component: String, to basePath: String) -> String {
        let normalizedBasePath = normalizeDisplayPath(basePath)
        if normalizedBasePath.isEmpty {
            return normalizeDisplayPath(component)
        }

        return normalizeDisplayPath("\(normalizedBasePath)/\(component)")
    }

    private func isSkippableDirectoryEntry(_ name: String) -> Bool {
        name == "." || name == ".."
    }

    private func cachedFileURL(for reference: RemoteComicFileReference) -> URL {
        var destinationURL = remoteComicCacheRootURL
            .appendingPathComponent(reference.serverID.uuidString, isDirectory: true)
            .appendingPathComponent(reference.shareName, isDirectory: true)

        let normalizedPath = shareRelativePath(forDisplayPath: reference.path)
        let components = normalizedPath
            .split(separator: "/")
            .map(String.init)

        if components.isEmpty {
            return destinationURL.appendingPathComponent(reference.fileName, isDirectory: false)
        }

        for component in components.dropLast() {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        return destinationURL.appendingPathComponent(
            components.last ?? reference.fileName,
            isDirectory: false
        )
    }

    private func isCachedComicCurrent(
        at fileURL: URL,
        reference: RemoteComicFileReference
    ) -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        guard let expectedFileSize = reference.fileSize else {
            return true
        }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        let cachedFileSize = values?.fileSize.map(Int64.init)
        return cachedFileSize == expectedFileSize
    }

    private func cacheRootURL(for profile: RemoteServerProfile?) -> URL {
        guard let profile else {
            return remoteComicCacheRootURL
        }

        return remoteComicCacheRootURL
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    private func touchCachedFile(at fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
    }

    private func trimCacheIfNeeded() throws {
        guard fileManager.fileExists(atPath: remoteComicCacheRootURL.path) else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: remoteComicCacheRootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var cachedFiles: [CachedComicFileRecord] = []
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true else {
                continue
            }

            let size = Int64(values?.fileSize ?? 0)
            totalBytes += size
            cachedFiles.append(
                CachedComicFileRecord(
                    url: fileURL,
                    size: size,
                    lastAccessDate: values?.contentModificationDate ?? .distantPast
                )
            )
        }

        guard cachedFiles.count > maximumCachedComicFileCount || totalBytes > maximumTotalCacheBytes else {
            return
        }

        let evictionCandidates = cachedFiles.sorted { lhs, rhs in
            lhs.lastAccessDate < rhs.lastAccessDate
        }

        var remainingFileCount = cachedFiles.count
        var remainingBytes = totalBytes

        for candidate in evictionCandidates {
            guard remainingFileCount > maximumCachedComicFileCount
                    || remainingBytes > maximumTotalCacheBytes
            else {
                break
            }

            do {
                try fileManager.removeItem(at: candidate.url)
                remainingFileCount -= 1
                remainingBytes -= candidate.size
            } catch {
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "The downloaded remote comic cache could not be trimmed automatically. \(error.localizedDescription)"
                )
            }
        }
    }

    private func normalizeBrowsingError(
        _ error: Error,
        profile: RemoteServerProfile,
        remotePath: String
    ) -> Error {
        if error is RemoteServerBrowsingError {
            return error
        }

        if let connectionError = error as? ConnectionError {
            switch connectionError {
            case .noData, .disconnected, .cancelled, .unknown:
                return RemoteServerBrowsingError.connectionFailed(profile.normalizedHost)
            }
        }

        if let responseError = error as? ErrorResponse {
            switch NTStatus(responseError.header.status) {
            case .logonFailure, .networkSessionExpired:
                return RemoteServerBrowsingError.authenticationFailed(profile.name)
            case .badNetworkName, .networkNameDeleted:
                return RemoteServerBrowsingError.shareUnavailable(profile.normalizedShareName)
            case .objectNameNotFound, .objectPathNotFound, .noSuchFile, .noSuchDevice:
                return RemoteServerBrowsingError.remotePathUnavailable(remotePath)
            case .accessDenied, .badImpersonationLevel:
                return RemoteServerBrowsingError.accessDenied(remotePath)
            case .connectionRefused, .ioTimeout:
                return RemoteServerBrowsingError.connectionFailed(profile.normalizedHost)
            default:
                let description = responseError.errorDescription ?? responseError.localizedDescription
                return RemoteServerBrowsingError.operationFailed(
                    "The SMB operation could not be completed. \(description)"
                )
            }
        }

        if let urlError = error as? URLError {
            return RemoteServerBrowsingError.connectionFailed(
                "\(profile.normalizedHost):\(profile.port) (\(urlError.localizedDescription))"
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return RemoteServerBrowsingError.connectionFailed(profile.normalizedHost)
        }

        return RemoteServerBrowsingError.operationFailed(error.localizedDescription)
    }

    private func cachedFallbackMessage(
        for error: Error,
        profile: RemoteServerProfile
    ) -> String {
        let normalizedError = normalizeBrowsingError(
            error,
            profile: profile,
            remotePath: profile.connectionDisplayPath
        )

        return "Opened the last downloaded copy because the server could not be reached. \(normalizedError.localizedDescription)"
    }
}

private struct CachedComicFileRecord {
    let url: URL
    let size: Int64
    let lastAccessDate: Date
}
