import CryptoKit
import Foundation
import ImageIO
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
    case insecureTransportBlocked(String)
    case certificateNotTrusted(String)
    case secureConnectionFailed(String)
    case cacheMaintenanceFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason):
            return reason
        case .providerIntegrationUnavailable(let providerKind):
            return "\(providerKind.title) browsing is planned but not wired into a live network client yet."
        case .unsupportedComicFile(let fileName):
            return "\(fileName) is not a supported remote comic."
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
        case .insecureTransportBlocked(let endpoint):
            return "iOS blocked the insecure HTTP connection to \(endpoint). Use HTTPS for this WebDAV server."
        case .certificateNotTrusted(let endpoint):
            return "The TLS certificate presented by \(endpoint) is not trusted by this device."
        case .secureConnectionFailed(let endpoint):
            return "A secure connection to \(endpoint) could not be established."
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
    let auxiliaryBytes: Int64

    static let empty = RemoteComicCacheSummary(fileCount: 0, totalBytes: 0, auxiliaryBytes: 0)

    init(fileCount: Int, totalBytes: Int64, auxiliaryBytes: Int64 = 0) {
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.auxiliaryBytes = max(0, auxiliaryBytes)
    }

    var isEmpty: Bool {
        totalBytes <= 0
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var summaryText: String {
        if fileCount <= 0 {
            return "Cached data · \(sizeText)"
        }

        if auxiliaryBytes > 0 {
            if fileCount == 1 {
                return "1 cached comic + other cache data · \(sizeText)"
            }

            return "\(fileCount) cached comics + other cache data · \(sizeText)"
        }

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

private struct RemoteListedDirectoryEntry: Sendable {
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?
}

private struct RemoteImageComicDirectoryInspection: Sendable {
    let pageEntries: [RemoteListedDirectoryEntry]
    let regularEntries: [RemoteListedDirectoryEntry]

    var pageCount: Int {
        pageEntries.count
    }

    var coverEntry: RemoteListedDirectoryEntry? {
        pageEntries.first
    }
}

private struct RemoteDirectoryPresentationInspection: Sendable {
    let imageComicInspection: RemoteImageComicDirectoryInspection?
    let previewItems: [RemoteDirectoryItem]
}

final class RemoteServerBrowsingService {
    private static let resumableDownloadChunkSize: UInt32 = 256 * 1024
    private static let downloadProgressReportingStep: Double = 0.01
    private static let batchDownloadWorkerLimit = 3
    private static let directoryInspectionTimeout: Duration = .milliseconds(350)
    private static let maxConsecutiveDirectoryInspectionSkips = 3
    private static let imageComicAuxiliaryFileNames: Set<String> = [
        "comicinfo.xml",
        "thumbs.db",
        "desktop.ini"
    ]
    private let supportedComicFileExtensions: Set<String> = [
        "cbz", "zip", "cbr", "rar", "cb7", "7z", "cbt", "tar", "pdf", "arj", "epub", "mobi"
    ]
    private let credentialStore: RemoteServerCredentialStore
    private let cachePolicyStore: RemoteCachePolicyStore
    private let webDAVClient: RemoteWebDAVClient
    private let fileManager: FileManager
    private let remoteComicCacheRootURL: URL
    private let cacheSummaryLock = NSLock()
    private var cacheSummariesByRootPath: [String: RemoteComicCacheSummary] = [:]
    private let automaticCacheTaskLock = NSLock()
    private var automaticCacheTaskCancellers: [String: @Sendable () -> Void] = [:]
    private let thumbnailSemaphore = AsyncSemaphore(maxConcurrent: 6)
    private let thumbnailSMBClientSemaphore = AsyncSemaphore(maxConcurrent: 2)
    private let downloadSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbClientSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbConnectionPool = SMBConnectionPool()
    private let webDAVRangeSupportStore = RemoteWebDAVRangeSupportStore()

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
            .appendingPathComponent("JamReader", isDirectory: true)
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

                var items: [RemoteDirectoryItem] = []
                items.reserveCapacity(entries.count)
                var consecutiveDirectoryInspectionSkips = 0
                var canInspectDirectories = true

                for entry in entries {
                    guard !isSkippableDirectoryEntry(entry.name) else {
                        continue
                    }

                    let fullPath = appendPathComponent(entry.name, to: requestedPath)
                    let inspection: RemoteDirectoryPresentationInspection?
                    if entry.isDirectory, canInspectDirectories {
                        inspection = try await inspectSMBDirectoryPresentationWithTimeout(
                            with: client,
                            directoryPath: fullPath,
                            profile: profile
                        )
                        if inspection == nil {
                            consecutiveDirectoryInspectionSkips += 1
                            if consecutiveDirectoryInspectionSkips >= Self.maxConsecutiveDirectoryInspectionSkips {
                                canInspectDirectories = false
                            }
                        } else {
                            consecutiveDirectoryInspectionSkips = 0
                        }
                    } else {
                        inspection = nil
                    }
                    items.append(
                        classifyDirectoryEntry(
                            named: entry.name,
                            fullPath: fullPath,
                            isDirectory: entry.isDirectory,
                            in: profile,
                            fileSize: Int64(clamping: entry.size),
                            modifiedAt: entry.lastWriteTime,
                            imageComicInspection: inspection?.imageComicInspection,
                            previewItems: inspection?.previewItems ?? []
                        )
                    )
                }

                return items
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

            var items: [RemoteDirectoryItem] = []
            items.reserveCapacity(entries.count)
            var consecutiveDirectoryInspectionSkips = 0
            var canInspectDirectories = true

            for entry in entries {
                guard let fullPath = displayPath(
                    forWebDAVEntryURL: entry.url,
                    collectionRootPath: collectionRootPath
                ),
                fullPath != requestedPath,
                !isSkippableDirectoryEntry(entry.name) else {
                    continue
                }

                let inspection: RemoteDirectoryPresentationInspection?
                if entry.isDirectory, canInspectDirectories {
                    inspection = try await inspectWebDAVDirectoryPresentationWithTimeout(
                        for: profile,
                        directoryPath: fullPath
                    )
                    if inspection == nil {
                        consecutiveDirectoryInspectionSkips += 1
                        if consecutiveDirectoryInspectionSkips >= Self.maxConsecutiveDirectoryInspectionSkips {
                            canInspectDirectories = false
                        }
                    } else {
                        consecutiveDirectoryInspectionSkips = 0
                    }
                } else {
                    inspection = nil
                }

                items.append(
                    classifyDirectoryEntry(
                        named: entry.name,
                        fullPath: fullPath,
                        isDirectory: entry.isDirectory,
                        in: profile,
                        fileSize: entry.fileSize,
                        modifiedAt: entry.modifiedAt,
                        imageComicInspection: inspection?.imageComicInspection,
                        previewItems: inspection?.previewItems ?? []
                    )
                )
            }

            return items
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
                        trimCacheAfterDownload: trimCacheAfterDownload,
                        progressHandler: progressHandler
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
                trimCacheAfterDownload: trimCacheAfterDownload,
                progressHandler: progressHandler
            ) { temporaryDownloadURL, resumeOffset in
                let fileURL = try webDAVURL(
                    for: profile,
                    displayPath: reference.path,
                    isDirectory: false
                )
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
            let outcomes = await concurrentBatchDownloadOutcomes(
                for: references,
                maximumConcurrency: Self.batchDownloadWorkerLimit
            ) { [downloadSemaphore] reference in
                await downloadSemaphore.wait(priority: .utility)
                defer { Task { await downloadSemaphore.signal() } }

                guard !Task.isCancelled else {
                    return RemoteComicBatchDownloadOutcome(
                        reference: reference,
                        result: nil,
                        error: CancellationError()
                    )
                }

                return await self.batchDownloadOutcome(for: reference) {
                    let result = try await self.withRetry(maxAttempts: 3, baseDelay: 1.0) {
                        try await self.withConnectedSMBClient(for: profile, priority: .utility) { client in
                            try await self.downloadComicFileCore(
                                for: profile,
                                reference: reference,
                                forceRefresh: forceRefresh,
                                trimCacheAfterDownload: trimCacheAfterDownload,
                                progressHandler: { fraction in
                                    progressHandler(reference, fraction)
                                }
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
            let outcomes = await concurrentBatchDownloadOutcomes(
                for: references,
                maximumConcurrency: Self.batchDownloadWorkerLimit
            ) { [downloadSemaphore] reference in
                await downloadSemaphore.wait(priority: .utility)
                defer { Task { await downloadSemaphore.signal() } }

                guard !Task.isCancelled else {
                    return RemoteComicBatchDownloadOutcome(
                        reference: reference,
                        result: nil,
                        error: CancellationError()
                    )
                }

                return await self.batchDownloadOutcome(for: reference) {
                    let result = try await self.downloadComicFileCore(
                        for: profile,
                        reference: reference,
                        forceRefresh: forceRefresh,
                        trimCacheAfterDownload: trimCacheAfterDownload,
                        progressHandler: { fraction in
                            progressHandler(reference, fraction)
                        }
                    ) { temporaryDownloadURL, resumeOffset in
                        let fileURL = try self.webDAVURL(
                            for: profile,
                            displayPath: reference.path,
                            isDirectory: false
                        )
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
                    totalBytes: partial.totalBytes + summary.totalBytes,
                    auxiliaryBytes: partial.auxiliaryBytes + summary.auxiliaryBytes
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

        let resources = enumerateCachedComicResources(in: cacheURL)
        let resourceBytes = resources.reduce(into: Int64.zero) { partialResult, resource in
            partialResult += resource.size
        }
        let totalBytes = DiskUsageScanner.allocatedByteCount(
            at: cacheURL,
            fileManager: fileManager
        )
        let summary = RemoteComicCacheSummary(
            fileCount: resources.count,
            totalBytes: totalBytes > 0 ? totalBytes : resourceBytes,
            auxiliaryBytes: max(0, totalBytes - resourceBytes)
        )
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
                "The downloaded remote comic cache could not be cleared. \(error.userFacingMessage)"
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
                "The downloaded remote comic cache could not be cleared. \(error.userFacingMessage)"
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
        cancelAutomaticCacheTask(for: reference)
        var removedAnyCachedFile = false

        for fileURL in allCachedResourceURLs(for: reference) {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                try? removeCachedMetadata(for: fileURL)
                try? resetPartialDownloadArtifacts(at: temporaryDownloadURL(for: fileURL))
                continue
            }

            do {
                try fileManager.removeItem(at: fileURL)
                try? removeCachedMetadata(for: fileURL)
                try? resetPartialDownloadArtifacts(at: temporaryDownloadURL(for: fileURL))
                try removeEmptyParentDirectories(
                    from: fileURL.deletingLastPathComponent(),
                    stoppingAt: cacheRootURL(for: nil)
                )
                removedAnyCachedFile = true
            } catch {
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "The downloaded copy could not be removed from this device. \(error.userFacingMessage)"
                )
            }
        }

        if removedAnyCachedFile {
            invalidateCachedSummaries()
        }
    }

    func cachedAvailability(for reference: RemoteComicFileReference) -> RemoteComicCachedAvailability {
        if currentCachedFileURL(for: reference) != nil {
            return RemoteComicCachedAvailability(kind: .current)
        }

        if anyCompatibleCachedFileURL(for: reference) != nil {
            return RemoteComicCachedAvailability(kind: .stale)
        }

        return .unavailable
    }

    func cachedFileURLIfAvailable(for reference: RemoteComicFileReference) -> URL? {
        currentCachedFileURL(for: reference) ?? anyCompatibleCachedFileURL(for: reference)
    }

    func plannedCachedFileURL(for reference: RemoteComicFileReference) -> URL {
        cachedFileURL(for: reference)
    }

    func supportsStreamingOpen(
        for reference: RemoteComicFileReference,
        profile: RemoteServerProfile
    ) async -> Bool {
        guard reference.providerKind == .smb || reference.providerKind == .webdav else {
            return false
        }

        guard reference.contentKind == .file else {
            return false
        }

        let fileExtension = URL(fileURLWithPath: reference.fileName).pathExtension.lowercased()
        switch fileExtension {
        case "cbz", "zip":
            if profile.providerKind == .webdav {
                return await webDAVRangeRequestsSupported(for: profile, reference: reference)
            }
            return true
        default:
            return false
        }
    }

    func allowsRemoteThumbnailFetch(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference
    ) async -> Bool {
        guard profile.providerKind == .webdav else {
            return true
        }

        return await webDAVRangeRequestsSupported(for: profile, reference: reference)
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
        if profile.providerKind == .webdav,
           !(await webDAVRangeRequestsSupported(for: profile, reference: reference)) {
            return nil
        }

        if reference.isImageDirectoryComic {
            return await fetchDirectImageDirectoryThumbnail(
                for: profile,
                reference: reference,
                maxPixelSize: maxPixelSize
            )
        }

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

    private func classifyDirectoryEntry(
        named name: String,
        fullPath: String,
        isDirectory: Bool,
        in profile: RemoteServerProfile,
        fileSize: Int64? = nil,
        modifiedAt: Date? = nil,
        imageComicInspection: RemoteImageComicDirectoryInspection? = nil,
        previewItems: [RemoteDirectoryItem] = []
    ) -> RemoteDirectoryItem {
        let kind: RemoteDirectoryItemKind
        if imageComicInspection != nil {
            kind = .comicDirectory
        } else if isDirectory {
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
            fileSize: imageComicInspection == nil ? fileSize : nil,
            modifiedAt: modifiedAt,
            pageCountHint: imageComicInspection?.pageCount,
            coverPath: imageComicInspection?.coverEntry?.fullPath,
            previewItems: previewItems
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
            modifiedAt: item.modifiedAt,
            contentKind: item.isComicDirectory ? .imageDirectory : .file,
            pageCountHint: item.pageCountHint,
            coverPath: item.coverPath
        )
    }

    func supportsComicFile(named fileName: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return supportedComicFileExtensions.contains(fileExtension)
    }

    private func supportsDirectoryPreviewComicFile(named fileName: String) -> Bool {
        guard supportsComicFile(named: fileName) else {
            return false
        }

        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return fileExtension != "pdf"
    }

    private func inspectSMBImageComicDirectory(
        with client: SMBClient,
        directoryPath: String
    ) async throws -> RemoteImageComicDirectoryInspection? {
        let listedEntries = try await listSMBEntries(
            with: client,
            directoryPath: directoryPath
        )
        return inspectImageComicDirectory(from: listedEntries)
    }

    private func inspectSMBDirectoryPresentation(
        with client: SMBClient,
        directoryPath: String,
        profile: RemoteServerProfile
    ) async throws -> RemoteDirectoryPresentationInspection {
        let listedEntries = try await listSMBEntries(
            with: client,
            directoryPath: directoryPath
        )
        let imageComicInspection = inspectImageComicDirectory(from: listedEntries)
        guard imageComicInspection == nil else {
            return RemoteDirectoryPresentationInspection(
                imageComicInspection: imageComicInspection,
                previewItems: []
            )
        }

        return RemoteDirectoryPresentationInspection(
            imageComicInspection: nil,
            previewItems: try await buildSMBPreviewItems(
                from: listedEntries,
                profile: profile
            )
        )
    }

    private func inspectSMBDirectoryPresentationWithTimeout(
        with client: SMBClient,
        directoryPath: String,
        profile: RemoteServerProfile
    ) async throws -> RemoteDirectoryPresentationInspection? {
        try await withDirectoryInspectionTimeout { [self] in
            try await self.inspectSMBDirectoryPresentation(
                with: client,
                directoryPath: directoryPath,
                profile: profile
            )
        }
    }

    private func inspectWebDAVImageComicDirectory(
        for profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> RemoteImageComicDirectoryInspection? {
        let directoryURL = try webDAVURL(
            for: profile,
            displayPath: directoryPath,
            isDirectory: true
        )
        let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
        let collectionRootPath = profile.webDAVBaseURL?.path ?? "/"
        let entries = try await webDAVClient.listDirectory(
            at: directoryURL,
            authorizationHeader: authorizationHeader
        )

        let listedEntries = listedWebDAVEntries(
            entries,
            directoryPath: directoryPath,
            collectionRootPath: collectionRootPath
        )

        return inspectImageComicDirectory(from: listedEntries)
    }

    private func inspectWebDAVDirectoryPresentation(
        for profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> RemoteDirectoryPresentationInspection {
        let directoryURL = try webDAVURL(
            for: profile,
            displayPath: directoryPath,
            isDirectory: true
        )
        let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
        let collectionRootPath = profile.webDAVBaseURL?.path ?? "/"
        let entries = try await webDAVClient.listDirectory(
            at: directoryURL,
            authorizationHeader: authorizationHeader
        )
        let listedEntries = listedWebDAVEntries(
            entries,
            directoryPath: directoryPath,
            collectionRootPath: collectionRootPath
        )
        let imageComicInspection = inspectImageComicDirectory(from: listedEntries)
        guard imageComicInspection == nil else {
            return RemoteDirectoryPresentationInspection(
                imageComicInspection: imageComicInspection,
                previewItems: []
            )
        }

        return RemoteDirectoryPresentationInspection(
            imageComicInspection: nil,
            previewItems: try await buildWebDAVPreviewItems(
                from: listedEntries,
                for: profile
            )
        )
    }

    private func inspectWebDAVDirectoryPresentationWithTimeout(
        for profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> RemoteDirectoryPresentationInspection? {
        try await withDirectoryInspectionTimeout { [self] in
            try await self.inspectWebDAVDirectoryPresentation(
                for: profile,
                directoryPath: directoryPath
            )
        }
    }

    private func withDirectoryInspectionTimeout<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                do {
                    return try await operation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return nil
                }
            }

            group.addTask {
                try await Task.sleep(for: Self.directoryInspectionTimeout)
                return nil
            }

            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func listSMBEntries(
        with client: SMBClient,
        directoryPath: String
    ) async throws -> [RemoteListedDirectoryEntry] {
        let entries = try await client.listDirectory(path: smbRelativePath(forDisplayPath: directoryPath))
        return entries.compactMap { entry -> RemoteListedDirectoryEntry? in
            guard !isSkippableDirectoryEntry(entry.name) else {
                return nil
            }

            return RemoteListedDirectoryEntry(
                name: entry.name,
                fullPath: appendPathComponent(entry.name, to: directoryPath),
                isDirectory: entry.isDirectory,
                fileSize: Int64(clamping: entry.size),
                modifiedAt: entry.lastWriteTime
            )
        }
    }

    private func listedWebDAVEntries(
        _ entries: [RemoteWebDAVDirectoryEntry],
        directoryPath: String,
        collectionRootPath: String
    ) -> [RemoteListedDirectoryEntry] {
        entries.compactMap { entry -> RemoteListedDirectoryEntry? in
            guard let fullPath = displayPath(
                forWebDAVEntryURL: entry.url,
                collectionRootPath: collectionRootPath
            ),
            fullPath != normalizeDisplayPath(directoryPath),
            !isSkippableDirectoryEntry(entry.name) else {
                return nil
            }

            return RemoteListedDirectoryEntry(
                name: entry.name,
                fullPath: fullPath,
                isDirectory: entry.isDirectory,
                fileSize: entry.fileSize,
                modifiedAt: entry.modifiedAt
            )
        }
    }

    private func buildSMBPreviewItems(
        from entries: [RemoteListedDirectoryEntry],
        profile: RemoteServerProfile
    ) async throws -> [RemoteDirectoryItem] {
        let sortedEntries = entries.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var previewItems: [RemoteDirectoryItem] = []

        for entry in sortedEntries {
            if !entry.isDirectory, supportsDirectoryPreviewComicFile(named: entry.name) {
                previewItems.append(
                    classifyDirectoryEntry(
                        named: entry.name,
                        fullPath: entry.fullPath,
                        isDirectory: false,
                        in: profile,
                        fileSize: entry.fileSize,
                        modifiedAt: entry.modifiedAt
                    )
                )
            }

            if previewItems.count >= 4 {
                return Array(previewItems.prefix(4))
            }
        }

        return previewItems
    }

    private func buildWebDAVPreviewItems(
        from entries: [RemoteListedDirectoryEntry],
        for profile: RemoteServerProfile
    ) async throws -> [RemoteDirectoryItem] {
        let sortedEntries = entries.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var previewItems: [RemoteDirectoryItem] = []

        for entry in sortedEntries {
            if !entry.isDirectory, supportsDirectoryPreviewComicFile(named: entry.name) {
                previewItems.append(
                    classifyDirectoryEntry(
                        named: entry.name,
                        fullPath: entry.fullPath,
                        isDirectory: false,
                        in: profile,
                        fileSize: entry.fileSize,
                        modifiedAt: entry.modifiedAt
                    )
                )
            }

            if previewItems.count >= 4 {
                return Array(previewItems.prefix(4))
            }
        }

        return previewItems
    }

    private func listWebDAVEntries(
        for profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> [RemoteListedDirectoryEntry] {
        let directoryURL = try webDAVURL(
            for: profile,
            displayPath: directoryPath,
            isDirectory: true
        )
        let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
        let collectionRootPath = profile.webDAVBaseURL?.path ?? "/"
        let entries = try await webDAVClient.listDirectory(
            at: directoryURL,
            authorizationHeader: authorizationHeader
        )
        return listedWebDAVEntries(
            entries,
            directoryPath: directoryPath,
            collectionRootPath: collectionRootPath
        )
    }

    private func inspectImageComicDirectory(
        from entries: [RemoteListedDirectoryEntry]
    ) -> RemoteImageComicDirectoryInspection? {
        let relevantEntries = entries.filter { !isSkippableImageComicEntry($0.name) }
        guard !relevantEntries.isEmpty,
              !relevantEntries.contains(where: \.isDirectory) else {
            return nil
        }

        let regularEntries = relevantEntries.filter { !$0.isDirectory }
        let pageEntries = regularEntries.filter { entry in
            ComicPageNameSorter.isSupportedImagePath(entry.name)
        }
        guard !pageEntries.isEmpty else {
            return nil
        }

        let relevantRegularEntries = regularEntries.filter { entry in
            !Self.imageComicAuxiliaryFileNames.contains(entry.name.lowercased())
        }
        guard !relevantRegularEntries.isEmpty else {
            return nil
        }

        let imageDominance = Double(pageEntries.count) / Double(relevantRegularEntries.count)
        guard imageDominance >= 0.8 else {
            return nil
        }

        let sortedPageNames = ComicPageNameSorter.sortedPageNames(pageEntries.map(\.name))
        let pageEntriesByName = Dictionary(uniqueKeysWithValues: pageEntries.map { ($0.name, $0) })
        let sortedPageEntries = sortedPageNames.compactMap { pageEntriesByName[$0] }
        guard !sortedPageEntries.isEmpty else {
            return nil
        }

        return RemoteImageComicDirectoryInspection(
            pageEntries: sortedPageEntries,
            regularEntries: regularEntries
        )
    }

    private func isSkippableImageComicEntry(_ name: String) -> Bool {
        isSkippableDirectoryEntry(name) || name.hasPrefix(".")
    }

    private func fetchDirectImageDirectoryThumbnail(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        maxPixelSize: Int
    ) async -> UIImage? {
        await thumbnailSemaphore.wait(priority: .utility)
        defer { Task { await thumbnailSemaphore.signal() } }

        let coverPath = await resolvedImageDirectoryCoverPath(for: profile, reference: reference)
        guard let coverPath,
              let imageData = await fetchRemoteImageData(
                for: profile,
                displayPath: coverPath
              ) else {
            return nil
        }

        return makeImageThumbnail(from: imageData, maxPixelSize: maxPixelSize)
    }

    private func resolvedImageDirectoryCoverPath(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference
    ) async -> String? {
        if let coverPath = reference.coverPath, !coverPath.isEmpty {
            return coverPath
        }

        switch profile.providerKind {
        case .smb:
            return try? await withThumbnailSMBClient(for: profile) { client in
                try await self.inspectSMBImageComicDirectory(
                    with: client,
                    directoryPath: reference.path
                )?.coverEntry?.fullPath
            }
        case .webdav:
            return try? await inspectWebDAVImageComicDirectory(
                for: profile,
                directoryPath: reference.path
            )?.coverEntry?.fullPath
        }
    }

    private func fetchRemoteImageData(
        for profile: RemoteServerProfile,
        displayPath: String
    ) async -> Data? {
        switch profile.providerKind {
        case .smb:
            return try? await withThumbnailSMBClient(for: profile) { client in
                let reader = client.fileReader(path: smbRelativePath(forDisplayPath: displayPath))
                do {
                    let data = try await reader.download()
                    try? await reader.close()
                    return data
                } catch {
                    try? await reader.close()
                    throw error
                }
            }
        case .webdav:
            guard let fileURL = try? webDAVURL(
                for: profile,
                displayPath: displayPath,
                isDirectory: false
            ),
            let authorizationHeader = try? resolvedAuthorizationHeader(for: profile) else {
                return nil
            }
            return try? await webDAVClient.downloadData(
                from: fileURL,
                authorizationHeader: authorizationHeader
            )
        }
    }

    private func webDAVRangeRequestsSupported(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference
    ) async -> Bool {
        guard profile.providerKind == .webdav else {
            return true
        }

        let cacheKey = profile.remoteCacheScopeKey
        if let cachedValue = await webDAVRangeSupportStore.value(for: cacheKey) {
            return cachedValue
        }

        let probePath = reference.isImageDirectoryComic ? reference.coverPath : reference.path
        guard let probePath,
              let probeURL = try? webDAVURL(
                for: profile,
                displayPath: probePath,
                isDirectory: false
              ),
              let authorizationHeader = try? resolvedAuthorizationHeader(for: profile) else {
            return true
        }

        do {
            let isSupported = try await webDAVClient.supportsRangeRequests(
                from: probeURL,
                authorizationHeader: authorizationHeader
            )
            await webDAVRangeSupportStore.store(isSupported, for: cacheKey)
            return isSupported
        } catch {
            return true
        }
    }

    private func makeImageThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
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
    /// Does NOT acquire `smbClientSemaphore`; thumbnail work uses its own
    /// narrower SMB gate so cover requests do not get starved by downloads
    /// or open an unbounded number of extra SMB sessions.
    private func withThumbnailSMBClient<T>(
        for profile: RemoteServerProfile,
        operation: (SMBClient) async throws -> T
    ) async throws -> T {
        await thumbnailSMBClientSemaphore.wait(priority: .utility)
        defer { Task { await thumbnailSMBClientSemaphore.signal() } }

        let credentials = try resolvedCredentials(for: profile)
        do {
            let client = SMBClient(
                host: profile.normalizedHost,
                port: profile.port,
                connectTimeout: 20
            )
            try await client.login(
                username: credentials.username,
                password: credentials.password
            )
            try await client.connectShare(profile.normalizedShareName)

            defer {
                Task {
                    _ = try? await client.disconnectShare()
                    _ = try? await client.logoff()
                    await MainActor.run {
                        client.session.disconnect()
                    }
                }
            }

            return try await operation(client)
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
        throw lastError ?? RemoteServerBrowsingError.operationFailed("Retry operation failed without a recorded error.")
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let browsingError = error as? RemoteServerBrowsingError {
            switch browsingError {
            case .connectionFailed:
                return true
            case .insecureTransportBlocked, .certificateNotTrusted, .secureConnectionFailed,
                 .authenticationFailed, .accessDenied, .invalidProfile,
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
        let entries = try await listDirectory(for: profile, path: displayPath)
        var comicItems: [RemoteDirectoryItem] = []

        for entry in entries {
            try Task.checkCancellation()
            if entry.isDirectory {
                let nestedComicFiles = try await recursivelyListComicFiles(
                    with: client,
                    for: profile,
                    displayPath: entry.path,
                    progressState: progressState,
                    progressHandler: progressHandler
                )
                comicItems.append(contentsOf: nestedComicFiles)
                continue
            }

            guard entry.canOpenAsComic else {
                continue
            }

            progressState.discoveredComicCount += 1
            progressHandler(progressState.discoveredComicCount, entry.path)
            comicItems.append(entry)
        }

        return comicItems
    }

    private func recursivelyListComicFiles(
        forWebDAVProfile profile: RemoteServerProfile,
        directoryPath: String
    ) async throws -> [RemoteDirectoryItem] {
        try Task.checkCancellation()
        let entries = try await listDirectory(for: profile, path: directoryPath)
        var comicItems: [RemoteDirectoryItem] = []

        for entry in entries {
            try Task.checkCancellation()
            if entry.isDirectory {
                let nestedComicFiles = try await recursivelyListComicFiles(
                    forWebDAVProfile: profile,
                    directoryPath: entry.path
                )
                comicItems.append(contentsOf: nestedComicFiles)
                continue
            }

            guard entry.canOpenAsComic else {
                continue
            }

            comicItems.append(entry)
        }

        return comicItems
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
        name == "." || name == ".." || name.hasPrefix(".")
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
        let rootComponents: [String]
        if let cacheScopeKey = reference.cacheScopeKey {
            rootComponents = cacheRootPathComponents(cacheScopeKey: cacheScopeKey)
        } else {
            rootComponents = legacyCacheRootPathComponents(
                providerKind: reference.providerKind,
                providerRootIdentifier: reference.shareName
            )
        }

        return cachedFileURL(for: reference, rootComponents: rootComponents)
    }

    private func legacyCachedFileURL(for reference: RemoteComicFileReference) -> URL {
        cachedFileURL(
            for: reference,
            rootComponents: legacyCacheRootPathComponents(
                providerKind: reference.providerKind,
                providerRootIdentifier: reference.shareName
            )
        )
    }

    private func cachedFileURL(
        for reference: RemoteComicFileReference,
        rootComponents: [String]
    ) -> URL {
        var destinationURL = remoteComicCacheRootURL
            .appendingPathComponent(reference.serverID.uuidString, isDirectory: true)
        for component in rootComponents {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        let normalizedPath = smbRelativePath(forDisplayPath: reference.path)
        let components = normalizedPath
            .split(separator: "/")
            .map(String.init)
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }

        if components.isEmpty {
            return destinationURL.appendingPathComponent(
                reference.fileName,
                isDirectory: reference.isImageDirectoryComic
            )
        }

        for component in components.dropLast() {
            destinationURL.appendPathComponent(component, isDirectory: true)
        }

        return destinationURL.appendingPathComponent(
            components.last ?? reference.fileName,
            isDirectory: reference.isImageDirectoryComic
        )
    }

    private func cachedFileCandidateURLs(for reference: RemoteComicFileReference) -> [URL] {
        let preferredURL = cachedFileURL(for: reference)
        let legacyURL = legacyCachedFileURL(for: reference)
        guard preferredURL.standardizedFileURL.path != legacyURL.standardizedFileURL.path else {
            return [preferredURL]
        }

        return [preferredURL, legacyURL]
    }

    private func allCachedResourceURLs(for reference: RemoteComicFileReference) -> [URL] {
        var ordered: [URL] = []
        var seenPaths = Set<String>()

        for candidateURL in cachedFileCandidateURLs(for: reference) + discoveredCachedResourceURLs(for: reference) {
            let standardizedPath = candidateURL.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            ordered.append(candidateURL)
        }

        return ordered
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

    func registerAutomaticCacheTask(
        for reference: RemoteComicFileReference,
        cancellation: @escaping @Sendable () -> Void
    ) {
        automaticCacheTaskLock.lock()
        automaticCacheTaskCancellers[reference.id] = cancellation
        automaticCacheTaskLock.unlock()
    }

    func unregisterAutomaticCacheTask(for reference: RemoteComicFileReference) {
        automaticCacheTaskLock.lock()
        automaticCacheTaskCancellers.removeValue(forKey: reference.id)
        automaticCacheTaskLock.unlock()
    }

    private func cancelAutomaticCacheTask(for reference: RemoteComicFileReference) {
        automaticCacheTaskLock.lock()
        let cancellation = automaticCacheTaskCancellers.removeValue(forKey: reference.id)
        automaticCacheTaskLock.unlock()
        cancellation?()
    }

    private func discoveredCachedResourceURLs(for reference: RemoteComicFileReference) -> [URL] {
        let serverRootURL = remoteComicCacheRootURL
            .appendingPathComponent(reference.serverID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: serverRootURL.path),
              let enumerator = fileManager.enumerator(
                at: serverRootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let candidateURL = item as? URL else {
                return nil
            }

            if isCacheAuxiliaryFile(candidateURL) {
                return nil
            }

            let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if reference.isImageDirectoryComic {
                guard values?.isDirectory == true else {
                    return nil
                }
            } else {
                guard values?.isRegularFile == true else {
                    return nil
                }
            }

            guard matchesCachedResource(candidateURL, serverRootURL: serverRootURL, reference: reference) else {
                return nil
            }

            return candidateURL
        }
    }

    private func matchesCachedResource(
        _ candidateURL: URL,
        serverRootURL: URL,
        reference: RemoteComicFileReference
    ) -> Bool {
        if let metadata = loadCachedMetadata(at: candidateURL) {
            guard metadata.contentKind == reference.contentKind else {
                return false
            }

            if let metadataPath = metadata.path {
                return normalizeDisplayPath(metadataPath) == normalizeDisplayPath(reference.path)
            }
        }

        let targetComponents = smbRelativePath(forDisplayPath: reference.path)
            .split(separator: "/")
            .map(String.init)
        guard !targetComponents.isEmpty else {
            return candidateURL.lastPathComponent == reference.fileName
        }

        let relativePath = candidateURL.standardizedFileURL.path
            .replacingOccurrences(of: serverRootURL.standardizedFileURL.path + "/", with: "")
        let candidateComponents = relativePath
            .split(separator: "/")
            .map(String.init)

        guard candidateComponents.count >= targetComponents.count else {
            return false
        }

        return Array(candidateComponents.suffix(targetComponents.count)) == targetComponents
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
        progressHandler: @escaping @Sendable (Double) -> Void,
        downloader: (URL, UInt64) async throws -> Void
    ) async throws -> RemoteComicDownloadResult {
        if reference.isImageDirectoryComic {
            return try await downloadImageDirectoryComicCore(
                for: profile,
                reference: reference,
                forceRefresh: forceRefresh,
                trimCacheAfterDownload: trimCacheAfterDownload,
                progressHandler: progressHandler
            )
        }

        let destinationURL = cachedFileURL(for: reference)
        if !forceRefresh,
           let currentCachedFileURL = currentCachedFileURL(for: reference) {
            touchCachedFile(at: currentCachedFileURL)
            return RemoteComicDownloadResult(localFileURL: currentCachedFileURL, source: .cachedCurrent)
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

    private func downloadImageDirectoryComicCore(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        forceRefresh: Bool,
        trimCacheAfterDownload: Bool,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> RemoteComicDownloadResult {
        let destinationURL = cachedFileURL(for: reference)
        if !forceRefresh,
           let currentCachedFileURL = currentCachedFileURL(for: reference) {
            touchCachedFile(at: currentCachedFileURL)
            return RemoteComicDownloadResult(localFileURL: currentCachedFileURL, source: .cachedCurrent)
        }

        let temporaryDirectoryURL = temporaryDownloadURL(for: destinationURL)

        do {
            if fileManager.fileExists(atPath: temporaryDirectoryURL.path) {
                try fileManager.removeItem(at: temporaryDirectoryURL)
            }

            try fileManager.createDirectory(
                at: temporaryDirectoryURL,
                withIntermediateDirectories: true
            )

            let inspection = try await imageDirectoryInspection(
                for: profile,
                reference: reference
            )

            let totalUnits = max(inspection.regularEntries.count, 1)
            var completedUnits = 0
            progressHandler(0)

            for entry in inspection.regularEntries {
                let completedUnitsBeforeDownload = completedUnits
                let localURL = temporaryDirectoryURL.appendingPathComponent(
                    entry.name,
                    isDirectory: false
                )
                try await downloadRemoteRegularFile(
                    for: profile,
                    remotePath: entry.fullPath,
                    to: localURL
                ) { fraction in
                    let normalizedFraction = min(max(fraction, 0), 1)
                    let aggregateProgress = (Double(completedUnitsBeforeDownload) + normalizedFraction) / Double(totalUnits)
                    progressHandler(aggregateProgress)
                }
                completedUnits += 1
                progressHandler(Double(completedUnits) / Double(totalUnits))
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryDirectoryURL, to: destinationURL)

            let cachedBytes = DiskUsageScanner.allocatedByteCount(
                at: destinationURL,
                fileManager: fileManager
            )
            try? storeCachedMetadata(
                for: reference,
                at: destinationURL,
                cachedByteCount: cachedBytes
            )
            touchCachedFile(at: destinationURL)
            if trimCacheAfterDownload {
                try? trimCacheIfNeeded()
            }
            invalidateCachedSummaries()
            progressHandler(1.0)

            return RemoteComicDownloadResult(localFileURL: destinationURL, source: .downloaded)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if fileManager.fileExists(atPath: temporaryDirectoryURL.path) {
                try? fileManager.removeItem(at: temporaryDirectoryURL)
            }

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

    private func imageDirectoryInspection(
        for profile: RemoteServerProfile,
        reference: RemoteComicFileReference
    ) async throws -> RemoteImageComicDirectoryInspection {
        switch profile.providerKind {
        case .smb:
            return try await withConnectedSMBClient(for: profile, priority: .utility) { client in
                guard let inspection = try await self.inspectSMBImageComicDirectory(
                    with: client,
                    directoryPath: reference.path
                ) else {
                    throw RemoteServerBrowsingError.unsupportedComicFile(reference.fileName)
                }
                return inspection
            }
        case .webdav:
            guard let inspection = try await inspectWebDAVImageComicDirectory(
                for: profile,
                directoryPath: reference.path
            ) else {
                throw RemoteServerBrowsingError.unsupportedComicFile(reference.fileName)
            }
            return inspection
        }
    }

    private func downloadRemoteRegularFile(
        for profile: RemoteServerProfile,
        remotePath: String,
        to localURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch profile.providerKind {
        case .smb:
            try await withConnectedSMBClient(for: profile, priority: .utility) { client in
                let reader = client.fileReader(path: smbRelativePath(forDisplayPath: remotePath))
                do {
                    try await reader.download(to: localURL, overwrite: true) { progress in
                        progressHandler(progress)
                    }
                    try? await reader.close()
                } catch {
                    try? await reader.close()
                    throw error
                }
            }
        case .webdav:
            let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
            let fileURL = try webDAVURL(
                for: profile,
                displayPath: remotePath,
                isDirectory: false
            )
            try await webDAVClient.download(
                from: fileURL,
                authorizationHeader: authorizationHeader,
                to: localURL
            )
            progressHandler(1.0)
        }
    }

    private func totalFileBytes(in directoryURL: URL) throws -> Int64 {
        DiskUsageScanner.allocatedByteCount(at: directoryURL, fileManager: fileManager)
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
        maximumConcurrency: Int,
        operation: @escaping @Sendable (RemoteComicFileReference) async -> RemoteComicBatchDownloadOutcome
    ) async -> [RemoteComicBatchDownloadOutcome] {
        guard !references.isEmpty else {
            return []
        }

        let workerCount = max(1, min(maximumConcurrency, references.count))

        return await withTaskGroup(of: (Int, RemoteComicBatchDownloadOutcome).self) { group in
            var nextIndex = 0

            func enqueueNextIfNeeded() {
                guard nextIndex < references.count else {
                    return
                }

                let index = nextIndex
                let reference = references[index]
                nextIndex += 1
                group.addTask(priority: .utility) {
                    (index, await operation(reference))
                }
            }

            for _ in 0..<workerCount {
                enqueueNextIfNeeded()
            }

            var orderedOutcomes: [RemoteComicBatchDownloadOutcome?] = Array(
                repeating: nil,
                count: references.count
            )
            for await (index, outcome) in group {
                orderedOutcomes[index] = outcome

                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }

                enqueueNextIfNeeded()
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
            if metadata.contentKind != reference.contentKind {
                return false
            }

            if let referenceCacheScopeKey = reference.cacheScopeKey {
                if let metadataCacheScopeKey = metadata.cacheScopeKey,
                   metadataCacheScopeKey != referenceCacheScopeKey {
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

        if reference.isImageDirectoryComic {
            return false
        }

        guard let expectedFileSize = reference.fileSize else {
            return true
        }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        let cachedFileSize = values?.fileSize.map(Int64.init)
        return cachedFileSize == expectedFileSize
    }

    private func currentCachedFileURL(for reference: RemoteComicFileReference) -> URL? {
        cachedFileCandidateURLs(for: reference).first { candidateURL in
            fileManager.fileExists(atPath: candidateURL.path)
                && isCachedComicCurrent(at: candidateURL, reference: reference)
        }
    }

    private func anyCompatibleCachedFileURL(for reference: RemoteComicFileReference) -> URL? {
        cachedFileCandidateURLs(for: reference).first { candidateURL in
            isCompatibleCachedComic(at: candidateURL, reference: reference)
        }
    }

    private func isCompatibleCachedComic(
        at fileURL: URL,
        reference: RemoteComicFileReference
    ) -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return false
        }

        if let metadata = loadCachedMetadata(at: fileURL) {
            guard metadata.contentKind == reference.contentKind else {
                return false
            }

            if let referenceCacheScopeKey = reference.cacheScopeKey,
               let metadataCacheScopeKey = metadata.cacheScopeKey,
               metadataCacheScopeKey != referenceCacheScopeKey {
                return false
            }

            return true
        }

        return !reference.isImageDirectoryComic
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
        at fileURL: URL,
        cachedByteCount: Int64? = nil
    ) throws {
        let metadata = CachedRemoteComicMetadata(
            cacheScopeKey: reference.cacheScopeKey,
            path: reference.path,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt,
            contentKind: reference.contentKind,
            cachedByteCount: cachedByteCount
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

        let cachedResources = enumerateCachedComicResources(in: remoteComicCacheRootURL)
        let totalBytes = cachedResources.reduce(into: Int64.zero) { partialResult, resource in
            partialResult += resource.size
        }

        guard cachedResources.count > cachePolicy.maximumCachedComicFileCount
                || totalBytes > cachePolicy.maximumTotalCacheBytes
        else {
            return
        }

        let evictionCandidates = cachedResources.sorted { lhs, rhs in
            lhs.lastAccessDate < rhs.lastAccessDate
        }

        var remainingFileCount = cachedResources.count
        var remainingBytes = totalBytes

        for candidate in evictionCandidates {
            guard remainingFileCount > cachePolicy.maximumCachedComicFileCount
                    || remainingBytes > cachePolicy.maximumTotalCacheBytes
            else {
                break
            }

            do {
                try fileManager.removeItem(at: candidate.resourceURL)
                try? removeCachedMetadata(for: candidate.resourceURL)
                try? removeEmptyParentDirectories(
                    from: candidate.resourceURL.deletingLastPathComponent(),
                    stoppingAt: remoteComicCacheRootURL
                )
                remainingFileCount -= 1
                remainingBytes -= candidate.size
            } catch {
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "The downloaded remote comic cache could not be trimmed automatically. \(error.userFacingMessage)"
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
            path: reference.path,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt,
            contentKind: reference.contentKind,
            cachedByteCount: nil
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
        if metadata.contentKind != reference.contentKind {
            return false
        }

        if let referenceCacheScopeKey = reference.cacheScopeKey,
           let metadataCacheScopeKey = metadata.cacheScopeKey,
           metadataCacheScopeKey != referenceCacheScopeKey {
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

    private func enumerateCachedComicResources(in rootURL: URL) -> [CachedComicResourceRecord] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var resources: [CachedComicResourceRecord] = []
        resources.reserveCapacity(128)

        for case let candidateURL as URL in enumerator {
            let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  isCachedMetadataSidecar(candidateURL) else {
                continue
            }

            let resourceURL = candidateURL.deletingPathExtension()
            guard fileManager.fileExists(atPath: resourceURL.path) else {
                continue
            }

            let metadata = (try? Data(contentsOf: candidateURL))
                .flatMap { try? JSONDecoder().decode(CachedRemoteComicMetadata.self, from: $0) }
            let size = metadata?.cachedByteCount ?? cachedResourceByteCount(at: resourceURL)
            let resourceValues = try? resourceURL.resourceValues(forKeys: [.contentModificationDateKey])

            resources.append(
                CachedComicResourceRecord(
                    resourceURL: resourceURL,
                    size: size,
                    lastAccessDate: resourceValues?.contentModificationDate ?? .distantPast
                )
            )
        }

        return resources
    }

    private func cachedResourceByteCount(at resourceURL: URL) -> Int64 {
        DiskUsageScanner.allocatedByteCount(at: resourceURL, fileManager: fileManager)
    }

    private func downloadRemoteFile(
        using reader: any RemoteRandomAccessFileReader,
        to temporaryDownloadURL: URL,
        resumeOffset requestedResumeOffset: UInt64,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        do {
            var lastReportedProgress: Double?
            func reportProgress(_ value: Double, force: Bool = false) {
                let clampedValue = min(max(value, 0), 1)
                if force
                    || lastReportedProgress == nil
                    || clampedValue >= 1
                    || clampedValue - (lastReportedProgress ?? 0) >= Self.downloadProgressReportingStep {
                    lastReportedProgress = clampedValue
                    progressHandler(clampedValue)
                }
            }

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
                reportProgress(1.0, force: true)
                try? await reader.close()
                return
            }

            reportProgress(Double(resumeOffset) / Double(remoteFileSize), force: true)

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
                reportProgress(min(Double(offset) / Double(remoteFileSize), 1.0))
            }

            reportProgress(1.0, force: true)
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
            return normalizedURLTransportError(
                code: urlError.code,
                profile: profile,
                fallbackMessage: urlError.localizedDescription
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let urlErrorCode = URLError.Code(rawValue: nsError.code)
            return normalizedURLTransportError(
                code: urlErrorCode,
                profile: profile,
                fallbackMessage: nsError.localizedDescription
            )
        }

        if nsError.domain == NSPOSIXErrorDomain {
            return RemoteServerBrowsingError.connectionFailed(profile.endpointDisplayHost)
        }

        return RemoteServerBrowsingError.operationFailed(error.userFacingMessage)
    }

    private func normalizedURLTransportError(
        code: URLError.Code,
        profile: RemoteServerProfile,
        fallbackMessage: String
    ) -> RemoteServerBrowsingError {
        switch code {
        case .appTransportSecurityRequiresSecureConnection:
            return .insecureTransportBlocked(profile.endpointDisplayHost)
        case .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid:
            return .certificateNotTrusted(profile.endpointDisplayHost)
        case .secureConnectionFailed,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .secureConnectionFailed(profile.endpointDisplayHost)
        default:
            return .connectionFailed("\(profile.endpointDisplayHost) (\(fallbackMessage))")
        }
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

private struct CachedComicResourceRecord {
    let resourceURL: URL
    let size: Int64
    let lastAccessDate: Date
}

private final class RecursiveListProgressState {
    var discoveredComicCount = 0
}

private actor RemoteWebDAVRangeSupportStore {
    private var valuesByScopeKey: [String: Bool] = [:]

    func value(for scopeKey: String) -> Bool? {
        valuesByScopeKey[scopeKey]
    }

    func store(_ value: Bool, for scopeKey: String) {
        valuesByScopeKey[scopeKey] = value
    }
}

private struct CachedRemoteComicMetadata: Codable {
    let cacheScopeKey: String?
    let path: String?
    let fileSize: Int64?
    let modifiedAt: Date?
    let contentKind: RemoteComicReferenceKind
    let cachedByteCount: Int64?

    private enum CodingKeys: String, CodingKey {
        case cacheScopeKey
        case path
        case fileSize
        case modifiedAt
        case contentKind
        case cachedByteCount
    }

    init(
        cacheScopeKey: String?,
        path: String?,
        fileSize: Int64?,
        modifiedAt: Date?,
        contentKind: RemoteComicReferenceKind,
        cachedByteCount: Int64?
    ) {
        self.cacheScopeKey = cacheScopeKey
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.contentKind = contentKind
        self.cachedByteCount = cachedByteCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cacheScopeKey = try container.decodeIfPresent(String.self, forKey: .cacheScopeKey)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        contentKind = try container.decodeIfPresent(RemoteComicReferenceKind.self, forKey: .contentKind) ?? .file
        cachedByteCount = try container.decodeIfPresent(Int64.self, forKey: .cachedByteCount)
    }
}
