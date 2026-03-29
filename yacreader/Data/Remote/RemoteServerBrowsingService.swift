import CryptoKit
import Foundation
import UIKit

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
            return "The remote location \(shareName) is not available right now."
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

struct RemoteComicBatchDownloadOutcome {
    let reference: RemoteComicFileReference
    let result: RemoteComicDownloadResult?
    let error: Error?
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

struct RemoteComicCachedAvailability: Hashable {
    enum Kind: Hashable {
        case unavailable
        case current
        case stale
    }

    let kind: Kind

    static let unavailable = RemoteComicCachedAvailability(kind: .unavailable)

    var hasLocalCopy: Bool {
        kind != .unavailable
    }

    var badgeTitle: String? {
        switch kind {
        case .unavailable:
            return nil
        case .current:
            return "Offline Ready"
        case .stale:
            return "Older Local Copy"
        }
    }
}

final class RemoteServerBrowsingService {
    private static let resumableDownloadChunkSize: UInt32 = 256 * 1024
    private let supportedComicFileExtensions: Set<String> = [
        "cbz", "zip", "cbr", "rar", "cb7", "7z", "cbt", "tar", "pdf"
    ]
    private let credentialStore: RemoteServerCredentialStore
    private let cachePolicyStore: RemoteCachePolicyStore
    private let webDAVClient: RemoteWebDAVClient
    private let fileManager: FileManager
    private let remoteComicCacheRootURL: URL
    private let cacheSummaryLock = NSLock()
    private var cacheSummariesByRootPath: [String: RemoteComicCacheSummary] = [:]
    private let thumbnailSemaphore = AsyncSemaphore(maxConcurrent: 6)
    private let downloadSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbClientSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbConnectionPool = SMBConnectionPool()

    init(
        credentialStore: RemoteServerCredentialStore = RemoteServerCredentialStore(),
        cachePolicyStore: RemoteCachePolicyStore = RemoteCachePolicyStore(),
        webDAVClient: RemoteWebDAVClient = RemoteWebDAVClient(),
        fileManager: FileManager = .default
    ) {
        self.credentialStore = credentialStore
        self.cachePolicyStore = cachePolicyStore
        self.webDAVClient = webDAVClient
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
                supportsSingleComicOpening: true
            )
        case .webdav:
            return RemoteServerBrowserCapabilities(
                providerKind: .webdav,
                supportsDirectoryBrowsing: true,
                supportsSingleComicOpening: true
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

        switch profile.providerKind {
        case .smb:
            if profile.normalizedShareName.isEmpty {
                issues.append(
                    RemoteServerValidationIssue(
                        severity: .error,
                        message: "Share name cannot be empty."
                    )
                )
            }
        case .webdav:
            if profile.webDAVBaseURL == nil {
                issues.append(
                    RemoteServerValidationIssue(
                        severity: .error,
                        message: "Enter a valid WebDAV host or URL."
                    )
                )
            }
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
                    message: "A saved password is required for this remote server."
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
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        let requestedPath = normalizeDisplayPath(path ?? profile.normalizedBaseDirectoryPath)
        switch profile.providerKind {
        case .smb:
            return try await withConnectedSMBClient(for: profile, priority: .userInitiated) { client in
                let shareRelativePath = smbRelativePath(forDisplayPath: requestedPath)
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
        case .webdav:
            let directoryURL = try webDAVURL(
                for: profile,
                displayPath: requestedPath,
                isDirectory: true
            )
            let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
            let collectionRootPath = profile.webDAVBaseURL?.path ?? "/"
            let entries = try await webDAVClient.listDirectory(
                at: directoryURL,
                authorizationHeader: authorizationHeader
            )

            return entries.compactMap { entry in
                guard let fullPath = displayPath(
                    forWebDAVEntryURL: entry.url,
                    collectionRootPath: collectionRootPath
                ),
                fullPath != requestedPath else {
                    return nil
                }

                return classifyDirectoryEntry(
                    named: entry.name,
                    fullPath: fullPath,
                    isDirectory: entry.isDirectory,
                    in: profile,
                    fileSize: entry.fileSize,
                    modifiedAt: entry.modifiedAt
                )
            }
        }
    }

    func listComicFilesRecursively(
        for profile: RemoteServerProfile,
        path: String? = nil,
        progressHandler: @escaping @Sendable (Int, String?) -> Void = { _, _ in }
    ) async throws -> [RemoteDirectoryItem] {
        try Task.checkCancellation()
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        let requestedPath = normalizeDisplayPath(path ?? profile.normalizedBaseDirectoryPath)
        switch profile.providerKind {
        case .smb:
            let progressState = RecursiveListProgressState()
            return try await withConnectedSMBClient(for: profile, priority: .userInitiated) { client in
                try await recursivelyListComicFiles(
                    with: client,
                    for: profile,
                    displayPath: requestedPath,
                    progressState: progressState,
                    progressHandler: progressHandler
                )
            }
        case .webdav:
            return try await recursivelyListComicFiles(
                forWebDAVProfile: profile,
                directoryPath: requestedPath
            )
        }
    }

    func downloadComicFile(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        forceRefresh: Bool = false,
        trimCacheAfterDownload: Bool = true
    ) async throws -> RemoteComicDownloadResult {
        try await downloadComicFile(
            for: profile,
            reference: reference,
            forceRefresh: forceRefresh,
            trimCacheAfterDownload: trimCacheAfterDownload,
            progressHandler: { _ in }
        )
    }

    func downloadComicFile(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        forceRefresh: Bool = false,
        trimCacheAfterDownload: Bool = true,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteComicDownloadResult {
        await downloadSemaphore.wait()
        defer { Task { await downloadSemaphore.signal() } }

        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        switch profile.providerKind {
        case .smb:
            return try await withRetry(maxAttempts: 3, baseDelay: 1.0) {
                try await withConnectedSMBClient(for: profile, priority: .utility) { client in
                    try await downloadComicFileCore(
                        for: profile,
                        reference: reference,
                        forceRefresh: forceRefresh,
                        trimCacheAfterDownload: trimCacheAfterDownload
                    ) { temporaryDownloadURL, resumeOffset in
                        let reader = client.fileReader(
                            path: smbRelativePath(forDisplayPath: reference.path)
                        )
                        try await downloadRemoteFile(
                            using: reader,
                            to: temporaryDownloadURL,
                            resumeOffset: resumeOffset,
                            progressHandler: progressHandler
                        )
                    }
                }
            }
        case .webdav:
            let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
            return try await downloadComicFileCore(
                for: profile,
                reference: reference,
                forceRefresh: forceRefresh,
                trimCacheAfterDownload: trimCacheAfterDownload
            ) { temporaryDownloadURL, resumeOffset in
                let fileURL = try webDAVURL(
                    for: profile,
                    displayPath: reference.path,
                    isDirectory: false
                )
                let reader = RemoteHTTPRangeFileReader(
                    url: fileURL,
                    authorizationHeader: authorizationHeader
                )

                do {
                    try await downloadRemoteFile(
                        using: reader,
                        to: temporaryDownloadURL,
                        resumeOffset: resumeOffset,
                        progressHandler: progressHandler
                    )
                } catch RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported {
                    try? await reader.close()
                    if resumeOffset > 0 {
                        try resetPartialDownloadArtifacts(at: temporaryDownloadURL)
                    }
                    try await webDAVClient.download(
                        from: fileURL,
                        authorizationHeader: authorizationHeader,
                        to: temporaryDownloadURL
                    )
                    progressHandler(1.0)
                }
            }
        }
    }

    func downloadComicFiles(
        for profile: RemoteServerProfile,
        references: [RemoteComicFileReference],
        forceRefresh: Bool = false,
        trimCacheAfterDownload: Bool = true,
        progressHandler: @escaping @Sendable (RemoteComicFileReference, Double) -> Void = { _, _ in }
    ) async throws -> [RemoteComicBatchDownloadOutcome] {
        try Task.checkCancellation()
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        switch profile.providerKind {
        case .smb:
            let outcomes = await concurrentBatchDownloadOutcomes(for: references) { [downloadSemaphore] reference in
                await downloadSemaphore.wait(priority: .utility)
                defer { Task { await downloadSemaphore.signal() } }

                return await self.batchDownloadOutcome(for: reference) {
                    let result = try await self.withRetry(maxAttempts: 3, baseDelay: 1.0) {
                        try await self.withConnectedSMBClient(for: profile, priority: .utility) { client in
                            try await self.downloadComicFileCore(
                                for: profile,
                                reference: reference,
                                forceRefresh: forceRefresh,
                                trimCacheAfterDownload: trimCacheAfterDownload
                            ) { temporaryDownloadURL, resumeOffset in
                                let reader = client.fileReader(
                                    path: self.smbRelativePath(forDisplayPath: reference.path)
                                )
                                try await self.downloadRemoteFile(
                                    using: reader,
                                    to: temporaryDownloadURL,
                                    resumeOffset: resumeOffset,
                                    progressHandler: { fraction in
                                        progressHandler(reference, fraction)
                                    }
                                )
                            }
                        }
                    }
                    progressHandler(reference, 1.0)
                    return result
                }
            }
            try Task.checkCancellation()
            return outcomes
        case .webdav:
            let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
            let outcomes = await concurrentBatchDownloadOutcomes(for: references) { [downloadSemaphore] reference in
                await downloadSemaphore.wait(priority: .utility)
                defer { Task { await downloadSemaphore.signal() } }

                return await self.batchDownloadOutcome(for: reference) {
                    let result = try await self.downloadComicFileCore(
                        for: profile,
                        reference: reference,
                        forceRefresh: forceRefresh,
                        trimCacheAfterDownload: trimCacheAfterDownload
                    ) { temporaryDownloadURL, resumeOffset in
                        let fileURL = try self.webDAVURL(
                            for: profile,
                            displayPath: reference.path,
                            isDirectory: false
                        )
                        let reader = RemoteHTTPRangeFileReader(
                            url: fileURL,
                            authorizationHeader: authorizationHeader
                        )

                        do {
                            try await self.downloadRemoteFile(
                                using: reader,
                                to: temporaryDownloadURL,
                                resumeOffset: resumeOffset,
                                progressHandler: { fraction in
                                    progressHandler(reference, fraction)
                                }
                            )
                        } catch RemoteHTTPRangeFileReaderError.rangeRequestsUnsupported {
                            try? await reader.close()
                            if resumeOffset > 0 {
                                try self.resetPartialDownloadArtifacts(at: temporaryDownloadURL)
                            }
                            try await self.webDAVClient.download(
                                from: fileURL,
                                authorizationHeader: authorizationHeader,
                                to: temporaryDownloadURL
                            )
                            progressHandler(reference, 1.0)
                        }
                    }
                    progressHandler(reference, 1.0)
                    return result
                }
            }
            try Task.checkCancellation()
            return outcomes
        }
    }

    func cacheSummary(for profile: RemoteServerProfile? = nil) -> RemoteComicCacheSummary {
        if let profile {
            return cacheRootURLs(for: profile).reduce(.empty) { partial, cacheURL in
                let summary = cacheSummary(forRootURL: cacheURL)
                return RemoteComicCacheSummary(
                    fileCount: partial.fileCount + summary.fileCount,
                    totalBytes: partial.totalBytes + summary.totalBytes
                )
            }
        }

        return cacheSummary(forRootURL: remoteComicCacheRootURL)
    }

    private func cacheSummary(forRootURL cacheURL: URL) -> RemoteComicCacheSummary {
        let cacheRootPath = cacheURL.standardizedFileURL.path

        cacheSummaryLock.lock()
        if let cachedSummary = cacheSummariesByRootPath[cacheRootPath] {
            cacheSummaryLock.unlock()
            return cachedSummary
        }
        cacheSummaryLock.unlock()

        guard fileManager.fileExists(atPath: cacheURL.path) else {
            storeCachedSummary(.empty, forRootPath: cacheRootPath)
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
            guard resourceValues?.isRegularFile == true,
                  !isCacheAuxiliaryFile(fileURL) else {
                continue
            }

            fileCount += 1
            totalBytes += Int64(resourceValues?.fileSize ?? 0)
        }

        let summary = RemoteComicCacheSummary(fileCount: fileCount, totalBytes: totalBytes)
        storeCachedSummary(summary, forRootPath: cacheRootPath)
        return summary
    }

    func cachePolicyPreset() -> RemoteComicCachePolicyPreset {
        cachePolicyStore.loadPreset()
    }

    func cachePolicy() -> RemoteComicCachePolicy {
        cachePolicyStore.loadPolicy()
    }

    func applyCachePolicyPreset(_ preset: RemoteComicCachePolicyPreset) throws {
        cachePolicyStore.savePreset(preset)
        try trimCacheIfNeeded()
        invalidateCachedSummaries()
    }

    func clearCachedComics(for profile: RemoteServerProfile? = nil) throws {
        do {
            for cacheURL in cacheRootURLs(for: profile) {
                guard fileManager.fileExists(atPath: cacheURL.path) else {
                    continue
                }

                try fileManager.removeItem(at: cacheURL)
            }
            invalidateCachedSummaries()
        } catch {
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The downloaded remote comic cache could not be cleared. \(error.localizedDescription)"
            )
        }
    }

    func clearCachedComicsForServer(id serverID: UUID) throws {
        let cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(serverID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: cacheURL)
            invalidateCachedSummaries()
        } catch {
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The downloaded remote comic cache could not be cleared. \(error.localizedDescription)"
            )
        }
    }

    func evictActiveConnections(for profile: RemoteServerProfile) {
        guard profile.providerKind == .smb else {
            return
        }

        Task {
            await smbConnectionPool.evictConnections(
                host: profile.normalizedHost,
                port: profile.port
            )
        }
    }

    func clearCachedComic(for reference: RemoteComicFileReference) throws {
        let fileURL = cachedFileURL(for: reference)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try? removeCachedMetadata(for: fileURL)
            try? resetPartialDownloadArtifacts(at: temporaryDownloadURL(for: fileURL))
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            try? removeCachedMetadata(for: fileURL)
            try? resetPartialDownloadArtifacts(at: temporaryDownloadURL(for: fileURL))
            try removeEmptyParentDirectories(
                from: fileURL.deletingLastPathComponent(),
                stoppingAt: cacheRootURL(for: nil)
            )
            invalidateCachedSummaries()
        } catch {
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The downloaded copy could not be removed from this device. \(error.localizedDescription)"
            )
        }
    }

    func cachedAvailability(for reference: RemoteComicFileReference) -> RemoteComicCachedAvailability {
        let destinationURL = cachedFileURL(for: reference)
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return .unavailable
        }

        if isCachedComicCurrent(at: destinationURL, reference: reference) {
            return RemoteComicCachedAvailability(kind: .current)
        }

        return RemoteComicCachedAvailability(kind: .stale)
    }

    func cachedFileURLIfAvailable(for reference: RemoteComicFileReference) -> URL? {
        let destinationURL = cachedFileURL(for: reference)
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return nil
        }

        return destinationURL
    }

    func plannedCachedFileURL(for reference: RemoteComicFileReference) -> URL {
        cachedFileURL(for: reference)
    }

    func supportsStreamingOpen(for reference: RemoteComicFileReference) -> Bool {
        let fileExtension = URL(fileURLWithPath: reference.fileName).pathExtension.lowercased()
        switch fileExtension {
        case "cbz", "zip":
            return true
        default:
            return false
        }
    }

    func makeStreamingFileReader(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference
    ) async throws -> any RemoteRandomAccessFileReader {
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        switch profile.providerKind {
        case .smb:
            let credentials = try resolvedCredentials(for: profile)
            return try await withRetry(maxAttempts: 3, baseDelay: 1.0) {
                do {
                    let client = SMBClient(host: profile.normalizedHost, port: profile.port, connectTimeout: 30)
                    try await client.login(
                        username: credentials.username,
                        password: credentials.password
                    )
                    try await client.connectShare(profile.normalizedShareName)
                    return ManagedSMBRemoteFileReader(
                        client: client,
                        fileReader: client.fileReader(
                            path: smbRelativePath(forDisplayPath: reference.path)
                        )
                    )
                } catch {
                    throw normalizeBrowsingError(
                        error,
                        profile: profile,
                        remotePath: reference.path
                    )
                }
            }
        case .webdav:
            return RemoteHTTPRangeFileReader(
                url: try webDAVURL(
                    for: profile,
                    displayPath: reference.path,
                    isDirectory: false
                ),
                authorizationHeader: try resolvedAuthorizationHeader(for: profile)
            )
        }
    }

    func fetchDirectThumbnail(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        maxPixelSize: Int
    ) async -> UIImage? {
        await thumbnailSemaphore.wait(priority: .utility)
        defer { Task { await thumbnailSemaphore.signal() } }

        let fileExtension = URL(fileURLWithPath: reference.fileName).pathExtension.lowercased()
        guard ["cbz", "zip", "cbt", "tar", "pdf", "cbr", "rar", "cb7", "7z", "arj"].contains(fileExtension) else {
            return nil
        }

        switch profile.providerKind {
        case .smb:
            // Thumbnails are already gated by thumbnailSemaphore(6); bypassing
            // smbClientSemaphore lets them proceed in parallel with downloads.
            return try? await withThumbnailSMBClient(for: profile) { client in
                let reader = client.fileReader(path: smbRelativePath(forDisplayPath: reference.path))
                do {
                    let image = try await extractDirectThumbnail(
                        fileExtension: fileExtension,
                        reader: reader,
                        maxPixelSize: maxPixelSize
                    )
                    try? await reader.close()
                    return image
                } catch {
                    try? await reader.close()
                    throw error
                }
            }
        case .webdav:
            guard let url = try? webDAVURL(
                for: profile,
                displayPath: reference.path,
                isDirectory: false
            ),
                  let authorizationHeader = try? resolvedAuthorizationHeader(for: profile) else {
                return nil
            }

            let reader = RemoteHTTPRangeFileReader(
                url: url,
                authorizationHeader: authorizationHeader
            )
            do {
                let image = try await extractDirectThumbnail(
                    fileExtension: fileExtension,
                    reader: reader,
                    maxPixelSize: maxPixelSize
                )
                try? await reader.close()
                return image
            } catch {
                try? await reader.close()
                return nil
            }
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
            shareName: profile.normalizedProviderRootIdentifier,
            cacheScopeKey: profile.remoteCacheScopeKey,
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
            cacheScopeKey: item.cacheScopeKey,
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

    private func withConnectedSMBClient<T>(
        for profile: RemoteServerProfile,
        connectTimeout: TimeInterval = 30,
        priority: TaskPriority = .medium,
        operation: (SMBClient) async throws -> T
    ) async throws -> T {
        await smbClientSemaphore.wait(priority: priority)
        defer { Task { await smbClientSemaphore.signal() } }

        let credentials = try resolvedCredentials(for: profile)

        do {
            return try await smbConnectionPool.withConnection(
                host: profile.normalizedHost,
                port: profile.port,
                shareName: profile.normalizedShareName,
                username: credentials.username,
                password: credentials.password,
                operation: operation
            )
        } catch {
            throw normalizeBrowsingError(
                error,
                profile: profile,
                remotePath: profile.connectionDisplayPath
            )
        }
    }

    /// Lightweight SMB connection accessor for thumbnail operations.
    /// Does NOT acquire `smbClientSemaphore` — thumbnail fetches are already
    /// bounded by `thumbnailSemaphore` (6 slots), so adding a second gate
    /// would block thumbnails whenever comic downloads saturate those 3 slots.
    private func withThumbnailSMBClient<T>(
        for profile: RemoteServerProfile,
        operation: (SMBClient) async throws -> T
    ) async throws -> T {
        let credentials = try resolvedCredentials(for: profile)
        do {
            return try await smbConnectionPool.withConnection(
                host: profile.normalizedHost,
                port: profile.port,
                shareName: profile.normalizedShareName,
                username: credentials.username,
                password: credentials.password,
                operation: operation
            )
        } catch {
            throw normalizeBrowsingError(
                error,
                profile: profile,
                remotePath: profile.connectionDisplayPath
            )
        }
    }

    /// Retries a throwing async operation with exponential backoff.
    /// Only retries on connection-level errors; authentication and path errors are not retried.
    private func withRetry<T>(
        maxAttempts: Int,
        baseDelay: TimeInterval,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                lastError = error
                guard isRetryableError(error), attempt < maxAttempts - 1 else {
                    throw error
                }
                let delay = baseDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        throw lastError!
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let browsingError = error as? RemoteServerBrowsingError {
            switch browsingError {
            case .connectionFailed:
                return true
            case .authenticationFailed, .accessDenied, .invalidProfile,
                 .missingCredentials, .unsupportedComicFile,
                 .shareUnavailable, .remotePathUnavailable,
                 .providerIntegrationUnavailable, .cacheMaintenanceFailed,
                 .operationFailed:
                return false
            }
        }
        if error is ConnectionError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain
    }

    private func recursivelyListComicFiles(
        with client: SMBClient,
        for profile: RemoteServerProfile,
        displayPath: String,
        progressState: RecursiveListProgressState,
        progressHandler: @escaping @Sendable (Int, String?) -> Void
    ) async throws -> [RemoteDirectoryItem] {
        try Task.checkCancellation()
        let shareRelativePath = smbRelativePath(forDisplayPath: displayPath)

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
            try Task.checkCancellation()
            guard !isSkippableDirectoryEntry(entry.name) else {
                continue
            }

            let fullPath = appendPathComponent(entry.name, to: displayPath)
            if entry.isDirectory {
                let nestedComicFiles = try await recursivelyListComicFiles(
                    with: client,
                    for: profile,
                    displayPath: fullPath,
                    progressState: progressState,
                    progressHandler: progressHandler
                )
                comicFiles.append(contentsOf: nestedComicFiles)
                continue
            }

            guard supportsComicFile(named: entry.name) else {
                continue
            }

            progressState.discoveredComicCount += 1
            progressHandler(progressState.discoveredComicCount, fullPath)
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

    private func recursivelyListComicFiles(
        forWebDAVProfile profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> [RemoteDirectoryItem] {
        try Task.checkCancellation()
        let requestedPath = normalizeDisplayPath(directoryPath)
        let directoryURL = try webDAVURL(
            for: profile,
            displayPath: requestedPath,
            isDirectory: true
        )
        let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
        let collectionRootPath = profile.webDAVBaseURL?.path ?? "/"

        do {
            let entries = try await webDAVClient.listDirectoryRecursively(
                at: directoryURL,
                authorizationHeader: authorizationHeader
            )

            return entries.compactMap { entry in
                guard let fullPath = displayPath(
                    forWebDAVEntryURL: entry.url,
                    collectionRootPath: collectionRootPath
                ),
                fullPath != requestedPath,
                supportsComicFile(named: entry.name),
                !entry.isDirectory else {
                    return nil
                }

                return classifyDirectoryEntry(
                    named: entry.name,
                    fullPath: fullPath,
                    isDirectory: false,
                    in: profile,
                    fileSize: entry.fileSize,
                    modifiedAt: entry.modifiedAt
                )
            }
        } catch let error as RemoteWebDAVClientError {
            switch error {
            case .authenticationFailed, .remotePathUnavailable, .connectionFailed:
                throw normalizeBrowsingError(error, profile: profile, remotePath: directoryPath)
            case .accessDenied, .invalidResponse, .unsupportedResponse:
                break
            }
        }

        let entries = try await listDirectory(for: profile, path: directoryPath)
        var comicFiles: [RemoteDirectoryItem] = []

        for entry in entries {
            try Task.checkCancellation()
            if entry.isDirectory {
                let nestedComicFiles = try await recursivelyListComicFiles(
                    forWebDAVProfile: profile,
                    directoryPath: entry.path
                )
                comicFiles.append(contentsOf: nestedComicFiles)
                continue
            }

            guard entry.canOpenAsComic else {
                continue
            }

            comicFiles.append(entry)
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
                    "This remote server needs a stored password before it can connect."
                )
            }

            guard let password = try credentialStore.loadPassword(for: passwordReferenceKey) else {
                throw RemoteServerBrowsingError.missingCredentials(
                    "The saved password for this remote server is missing. Edit the server and save the password again."
                )
            }

            return (profile.username, password)
        }
    }

    private func resolvedAuthorizationHeader(
        for profile: RemoteServerProfile
    ) throws -> String? {
        let credentials = try resolvedCredentials(for: profile)
        return webDAVClient.authorizationHeader(
            username: credentials.username,
            password: credentials.password
        )
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

    private func smbRelativePath(forDisplayPath path: String) -> String {
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

    private func webDAVURL(
        for profile: RemoteServerProfile,
        displayPath: String,
        isDirectory: Bool
    ) throws -> URL {
        guard let baseURL = profile.webDAVBaseURL else {
            throw RemoteServerBrowsingError.invalidProfile("The WebDAV server profile is incomplete.")
        }

        let pathComponents = normalizeDisplayPath(displayPath)
            .split(separator: "/")
            .map(String.init)

        guard !pathComponents.isEmpty else {
            return baseURL
        }

        return pathComponents.enumerated().reduce(baseURL) { url, element in
            let isLastComponent = element.offset == pathComponents.count - 1
            let appendsDirectoryComponent = isLastComponent ? isDirectory : true
            return url.appendingPathComponent(
                element.element,
                isDirectory: appendsDirectoryComponent
            )
        }
    }

    private func displayPath(
        forWebDAVEntryURL url: URL,
        collectionRootPath: String
    ) -> String? {
        let normalizedEntryPath = normalizeDisplayPath(url.path)
        let normalizedRootPath = normalizeDisplayPath(collectionRootPath)
        let rootComponents = normalizedRootPath
            .split(separator: "/")
            .map(String.init)
        let entryComponents = normalizedEntryPath
            .split(separator: "/")
            .map(String.init)

        guard entryComponents.count >= rootComponents.count,
              Array(entryComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }

        let relativeComponents = Array(entryComponents.dropFirst(rootComponents.count))
        guard !relativeComponents.isEmpty else {
            return ""
        }

        return "/" + relativeComponents.joined(separator: "/")
    }

    private func cachedFileURL(for reference: RemoteComicFileReference) -> URL {
        var destinationURL = remoteComicCacheRootURL
            .appendingPathComponent(reference.serverID.uuidString, isDirectory: true)
        let rootComponents: [String]
        if let cacheScopeKey = reference.cacheScopeKey {
            rootComponents = cacheRootPathComponents(cacheScopeKey: cacheScopeKey)
        } else {
            rootComponents = legacyCacheRootPathComponents(
                providerKind: reference.providerKind,
                providerRootIdentifier: reference.shareName
            )
        }

        for component in rootComponents {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        let normalizedPath = smbRelativePath(forDisplayPath: reference.path)
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

    private func legacyCacheRootPathComponents(
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String
    ) -> [String] {
        switch providerKind {
        case .smb:
            let trimmed = providerRootIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            return [trimmed.isEmpty ? "share" : trimmed]
        case .webdav:
            let components = normalizeDisplayPath(providerRootIdentifier)
                .split(separator: "/")
                .map(String.init)
            return components.isEmpty ? ["webdav-root"] : ["webdav"] + components
        }
    }

    private func cacheRootPathComponents(cacheScopeKey: String) -> [String] {
        let digest = SHA256.hash(data: Data(cacheScopeKey.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return ["scope-\(digest)"]
    }

    private func extractDirectThumbnail(
        fileExtension: String,
        reader: any RemoteRandomAccessFileReader,
        maxPixelSize: Int
    ) async throws -> UIImage {
        switch fileExtension {
        case "cbz", "zip":
            return try await RemoteZIPThumbnailExtractor(fileReader: reader)
                .extractThumbnail(maxPixelSize: maxPixelSize)
        case "cbt", "tar":
            return try await RemoteTARThumbnailExtractor(fileReader: reader)
                .extractThumbnail(maxPixelSize: maxPixelSize)
        case "pdf":
            return try await RemotePDFThumbnailExtractor(fileReader: reader)
                .extractThumbnail(maxPixelSize: maxPixelSize)
        case "cbr", "rar", "cb7", "7z", "arj":
            return try await RemoteLibArchiveThumbnailExtractor(fileReader: reader)
                .extractThumbnail(maxPixelSize: maxPixelSize)
        default:
            throw RemoteServerBrowsingError.operationFailed("Unsupported thumbnail format.")
        }
    }

    private func downloadComicFileCore(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        forceRefresh: Bool,
        trimCacheAfterDownload: Bool,
        downloader: (URL, UInt64) async throws -> Void
    ) async throws -> RemoteComicDownloadResult {
        let destinationURL = cachedFileURL(for: reference)
        if !forceRefresh, isCachedComicCurrent(at: destinationURL, reference: reference) {
            touchCachedFile(at: destinationURL)
            return RemoteComicDownloadResult(localFileURL: destinationURL, source: .cachedCurrent)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryDownloadURL = temporaryDownloadURL(for: destinationURL)
        let resumeOffset = try preparePartialDownload(
            at: temporaryDownloadURL,
            reference: reference
        )

        do {
            try await downloader(temporaryDownloadURL, resumeOffset)
            try Task.checkCancellation()

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryDownloadURL, to: destinationURL)
            try? removePartialDownloadMetadata(at: temporaryDownloadURL)
            try? storeCachedMetadata(for: reference, at: destinationURL)
            touchCachedFile(at: destinationURL)
            if trimCacheAfterDownload {
                try? trimCacheIfNeeded()
            }
            invalidateCachedSummaries()
            return RemoteComicDownloadResult(localFileURL: destinationURL, source: .downloaded)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
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

    private func batchDownloadOutcome(
        for reference: RemoteComicFileReference,
        operation: () async throws -> RemoteComicDownloadResult
    ) async -> RemoteComicBatchDownloadOutcome {
        do {
            return RemoteComicBatchDownloadOutcome(
                reference: reference,
                result: try await operation(),
                error: nil
            )
        } catch {
            return RemoteComicBatchDownloadOutcome(
                reference: reference,
                result: nil,
                error: error
            )
        }
    }

    private func concurrentBatchDownloadOutcomes(
        for references: [RemoteComicFileReference],
        operation: @escaping @Sendable (RemoteComicFileReference) async -> RemoteComicBatchDownloadOutcome
    ) async -> [RemoteComicBatchDownloadOutcome] {
        guard !references.isEmpty else {
            return []
        }

        return await withTaskGroup(of: (Int, RemoteComicBatchDownloadOutcome).self) { group in
            for (index, reference) in references.enumerated() {
                group.addTask(priority: .utility) {
                    (index, await operation(reference))
                }
            }

            var orderedOutcomes: [RemoteComicBatchDownloadOutcome?] = Array(
                repeating: nil,
                count: references.count
            )
            for await (index, outcome) in group {
                orderedOutcomes[index] = outcome
            }

            return orderedOutcomes.compactMap { $0 }
        }
    }

    private func isCachedComicCurrent(
        at fileURL: URL,
        reference: RemoteComicFileReference
    ) -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        if let metadata = loadCachedMetadata(at: fileURL) {
            if let referenceCacheScopeKey = reference.cacheScopeKey {
                guard metadata.cacheScopeKey == referenceCacheScopeKey else {
                    return false
                }
            }

            if let expectedFileSize = reference.fileSize,
               metadata.fileSize != expectedFileSize {
                return false
            }

            if let expectedModifiedAt = reference.modifiedAt,
               let cachedModifiedAt = metadata.modifiedAt,
               abs(cachedModifiedAt.timeIntervalSince(expectedModifiedAt)) > 1 {
                return false
            }

            if reference.fileSize != nil || reference.modifiedAt != nil {
                return true
            }
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

        var cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        for component in cacheRootPathComponents(cacheScopeKey: profile.remoteCacheScopeKey) {
            cacheURL.appendPathComponent(component, isDirectory: true)
        }

        return cacheURL
    }

    private func legacyCacheRootURL(for profile: RemoteServerProfile) -> URL {
        var cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        for component in legacyCacheRootPathComponents(
            providerKind: profile.providerKind,
            providerRootIdentifier: profile.normalizedProviderRootIdentifier
        ) {
            cacheURL.appendPathComponent(component, isDirectory: true)
        }

        return cacheURL
    }

    private func cacheRootURLs(for profile: RemoteServerProfile?) -> [URL] {
        guard let profile else {
            return [remoteComicCacheRootURL]
        }

        var ordered: [URL] = []
        var seenPaths = Set<String>()
        for url in [cacheRootURL(for: profile), legacyCacheRootURL(for: profile)] {
            let standardizedPath = url.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            ordered.append(url)
        }
        return ordered
    }

    private func cachedMetadataURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("yacmeta")
    }

    private func isCachedMetadataSidecar(_ fileURL: URL) -> Bool {
        fileURL.pathExtension == "yacmeta"
    }

    private func isPartialDownloadMetadataSidecar(_ fileURL: URL) -> Bool {
        fileURL.pathExtension == "yacpartial"
    }

    private func isPartialDownloadFile(_ fileURL: URL) -> Bool {
        fileURL.pathExtension == "download"
    }

    private func isCacheAuxiliaryFile(_ fileURL: URL) -> Bool {
        isCachedMetadataSidecar(fileURL)
            || isPartialDownloadMetadataSidecar(fileURL)
            || isPartialDownloadFile(fileURL)
    }

    private func loadCachedMetadata(at fileURL: URL) -> CachedRemoteComicMetadata? {
        let metadataURL = cachedMetadataURL(for: fileURL)
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL)
        else {
            return nil
        }

        return try? JSONDecoder().decode(CachedRemoteComicMetadata.self, from: data)
    }

    private func storeCachedMetadata(
        for reference: RemoteComicFileReference,
        at fileURL: URL
    ) throws {
        let metadata = CachedRemoteComicMetadata(
            cacheScopeKey: reference.cacheScopeKey,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: cachedMetadataURL(for: fileURL), options: .atomic)
    }

    private func removeCachedMetadata(for fileURL: URL) throws {
        let metadataURL = cachedMetadataURL(for: fileURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        try fileManager.removeItem(at: metadataURL)
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

    private func storeCachedSummary(_ summary: RemoteComicCacheSummary, forRootPath rootPath: String) {
        cacheSummaryLock.lock()
        cacheSummariesByRootPath[rootPath] = summary
        cacheSummaryLock.unlock()
    }

    private func invalidateCachedSummaries() {
        cacheSummaryLock.lock()
        cacheSummariesByRootPath.removeAll()
        cacheSummaryLock.unlock()
    }

    private func trimCacheIfNeeded() throws {
        guard fileManager.fileExists(atPath: remoteComicCacheRootURL.path) else {
            return
        }

        let cachePolicy = cachePolicyStore.loadPolicy()

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
            guard values?.isRegularFile == true,
                  !isCacheAuxiliaryFile(fileURL) else {
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

        guard cachedFiles.count > cachePolicy.maximumCachedComicFileCount
                || totalBytes > cachePolicy.maximumTotalCacheBytes
        else {
            return
        }

        let evictionCandidates = cachedFiles.sorted { lhs, rhs in
            lhs.lastAccessDate < rhs.lastAccessDate
        }

        var remainingFileCount = cachedFiles.count
        var remainingBytes = totalBytes

        for candidate in evictionCandidates {
            guard remainingFileCount > cachePolicy.maximumCachedComicFileCount
                    || remainingBytes > cachePolicy.maximumTotalCacheBytes
            else {
                break
            }

            do {
                try fileManager.removeItem(at: candidate.url)
                try? removeCachedMetadata(for: candidate.url)
                remainingFileCount -= 1
                remainingBytes -= candidate.size
            } catch {
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "The downloaded remote comic cache could not be trimmed automatically. \(error.localizedDescription)"
                )
            }
        }
    }

    private func removeEmptyParentDirectories(from startURL: URL, stoppingAt rootURL: URL) throws {
        var currentURL = startURL.standardizedFileURL
        let normalizedRootURL = rootURL.standardizedFileURL

        while currentURL.path.hasPrefix(normalizedRootURL.path), currentURL != normalizedRootURL {
            let contents = try fileManager.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: nil
            )
            guard contents.isEmpty else {
                break
            }

            try fileManager.removeItem(at: currentURL)
            currentURL.deleteLastPathComponent()
        }
    }

    private func temporaryDownloadURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("download")
    }

    private func partialDownloadMetadataURL(for temporaryDownloadURL: URL) -> URL {
        temporaryDownloadURL.appendingPathExtension("yacpartial")
    }

    private func loadPartialDownloadMetadata(at temporaryDownloadURL: URL) -> CachedRemoteComicMetadata? {
        let metadataURL = partialDownloadMetadataURL(for: temporaryDownloadURL)
        guard fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL)
        else {
            return nil
        }

        return try? JSONDecoder().decode(CachedRemoteComicMetadata.self, from: data)
    }

    private func storePartialDownloadMetadata(
        for reference: RemoteComicFileReference,
        at temporaryDownloadURL: URL
    ) throws {
        let metadata = CachedRemoteComicMetadata(
            cacheScopeKey: reference.cacheScopeKey,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: partialDownloadMetadataURL(for: temporaryDownloadURL), options: .atomic)
    }

    private func removePartialDownloadMetadata(at temporaryDownloadURL: URL) throws {
        let metadataURL = partialDownloadMetadataURL(for: temporaryDownloadURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return
        }

        try fileManager.removeItem(at: metadataURL)
    }

    private func resetPartialDownloadArtifacts(at temporaryDownloadURL: URL) throws {
        if fileManager.fileExists(atPath: temporaryDownloadURL.path) {
            try fileManager.removeItem(at: temporaryDownloadURL)
        }
        try? removePartialDownloadMetadata(at: temporaryDownloadURL)
    }

    private func preparePartialDownload(
        at temporaryDownloadURL: URL,
        reference: RemoteComicFileReference
    ) throws -> UInt64 {
        let hasPartialFile = fileManager.fileExists(atPath: temporaryDownloadURL.path)
        let hasCompatibleMetadata: Bool

        if let metadata = loadPartialDownloadMetadata(at: temporaryDownloadURL) {
            hasCompatibleMetadata = partialDownloadMetadataMatches(metadata, reference: reference)
        } else {
            hasCompatibleMetadata = false
        }

        if hasPartialFile && !hasCompatibleMetadata {
            try resetPartialDownloadArtifacts(at: temporaryDownloadURL)
        } else if !hasPartialFile {
            try? removePartialDownloadMetadata(at: temporaryDownloadURL)
        }

        if !fileManager.fileExists(atPath: temporaryDownloadURL.path) {
            try Data().write(to: temporaryDownloadURL, options: .atomic)
        }

        try storePartialDownloadMetadata(for: reference, at: temporaryDownloadURL)

        let values = try temporaryDownloadURL.resourceValues(forKeys: [.fileSizeKey])
        let partialSize = max(values.fileSize ?? 0, 0)
        return UInt64(partialSize)
    }

    private func partialDownloadMetadataMatches(
        _ metadata: CachedRemoteComicMetadata,
        reference: RemoteComicFileReference
    ) -> Bool {
        if let referenceCacheScopeKey = reference.cacheScopeKey,
           metadata.cacheScopeKey != referenceCacheScopeKey {
            return false
        }

        if let expectedFileSize = reference.fileSize,
           metadata.fileSize != expectedFileSize {
            return false
        }

        if let expectedModifiedAt = reference.modifiedAt {
            guard let cachedModifiedAt = metadata.modifiedAt else {
                return false
            }

            if abs(cachedModifiedAt.timeIntervalSince(expectedModifiedAt)) > 1 {
                return false
            }
        }

        if reference.fileSize != nil || reference.modifiedAt != nil {
            return true
        }

        return metadata.fileSize == nil && metadata.modifiedAt == nil
    }

    private func downloadRemoteFile(
        using reader: any RemoteRandomAccessFileReader,
        to temporaryDownloadURL: URL,
        resumeOffset requestedResumeOffset: UInt64,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        do {
            try Task.checkCancellation()
            let remoteFileSize = try await reader.fileSize

            guard let fileHandle = FileHandle(forWritingAtPath: temporaryDownloadURL.path) else {
                throw URLError(.cannotWriteToFile)
            }
            defer {
                fileHandle.closeFile()
            }

            let resumeOffset: UInt64
            if requestedResumeOffset > remoteFileSize {
                fileHandle.truncateFile(atOffset: 0)
                resumeOffset = 0
            } else {
                fileHandle.truncateFile(atOffset: requestedResumeOffset)
                resumeOffset = requestedResumeOffset
            }

            guard remoteFileSize > 0 else {
                progressHandler(1.0)
                try? await reader.close()
                return
            }

            progressHandler(Double(resumeOffset) / Double(remoteFileSize))

            var offset = resumeOffset
            while offset < remoteFileSize {
                try Task.checkCancellation()

                let remainingBytes = remoteFileSize - offset
                let chunkLength = UInt32(min(UInt64(Self.resumableDownloadChunkSize), remainingBytes))
                let data = try await reader.read(offset: offset, length: chunkLength)
                guard !data.isEmpty else {
                    throw RemoteServerBrowsingError.operationFailed(
                        "The remote download stopped before the file was complete."
                    )
                }

                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                offset += UInt64(data.count)
                progressHandler(min(Double(offset) / Double(remoteFileSize), 1.0))
            }

            progressHandler(1.0)
            try? await reader.close()
        } catch {
            try? await reader.close()
            throw error
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
                return RemoteServerBrowsingError.connectionFailed(profile.endpointDisplayHost)
            case .connectionTimeout:
                return RemoteServerBrowsingError.connectionFailed(
                    "\(profile.endpointDisplayHost) (connection timed out)"
                )
            }
        }

        if let webDAVError = error as? RemoteWebDAVClientError {
            switch webDAVError {
            case .authenticationFailed:
                return RemoteServerBrowsingError.authenticationFailed(profile.name)
            case .accessDenied:
                return RemoteServerBrowsingError.accessDenied(remotePath)
            case .remotePathUnavailable:
                return RemoteServerBrowsingError.remotePathUnavailable(remotePath)
            case .connectionFailed(let message):
                return RemoteServerBrowsingError.connectionFailed(message)
            case .invalidResponse, .unsupportedResponse:
                return RemoteServerBrowsingError.operationFailed(webDAVError.localizedDescription)
            }
        }

        if let responseError = error as? ErrorResponse {
            switch NTStatus(responseError.header.status) {
            case .logonFailure, .networkSessionExpired:
                return RemoteServerBrowsingError.authenticationFailed(profile.name)
            case .badNetworkName, .networkNameDeleted:
                return RemoteServerBrowsingError.shareUnavailable(profile.normalizedProviderRootIdentifier)
            case .objectNameNotFound, .objectPathNotFound, .noSuchFile, .noSuchDevice:
                return RemoteServerBrowsingError.remotePathUnavailable(remotePath)
            case .accessDenied, .badImpersonationLevel:
                return RemoteServerBrowsingError.accessDenied(remotePath)
            case .connectionRefused, .ioTimeout:
                return RemoteServerBrowsingError.connectionFailed(profile.endpointDisplayHost)
            default:
                let description = responseError.errorDescription ?? responseError.localizedDescription
                return RemoteServerBrowsingError.operationFailed(
                    "The remote operation could not be completed. \(description)"
                )
            }
        }

        if let urlError = error as? URLError {
            return RemoteServerBrowsingError.connectionFailed(
                "\(profile.endpointDisplayHost) (\(urlError.localizedDescription))"
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return RemoteServerBrowsingError.connectionFailed(profile.endpointDisplayHost)
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

private final class RecursiveListProgressState {
    var discoveredComicCount = 0
}

private struct CachedRemoteComicMetadata: Codable {
    let cacheScopeKey: String?
    let fileSize: Int64?
    let modifiedAt: Date?
}
