import Foundation
import ImageIO
import os
import UIKit

private struct RemoteListedDirectoryEntry: Sendable {
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?
}

private struct AuxiliaryCacheResourceRecord: Sendable {
    let resourceURL: URL
    let size: Int64
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
    private struct AutomaticCacheTaskRecord {
        let serverID: UUID
        let cancellation: @Sendable () -> Void
    }

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
    private let supportedComicFileExtensions = SupportedComicFormats.comicFileExtensions
    private let credentialStore: RemoteServerCredentialStore
    private let cachePolicyStore: RemoteCachePolicyStore
    private let webDAVClient: RemoteWebDAVClient
    private let fileManager: FileManager
    private let remoteComicCacheRootURL: URL
    private let cachePathResolver: RemoteCachePathResolver
    private let cacheSummaryLock = NSLock()
    private var cacheSummariesByRootPath: [String: RemoteComicCacheSummary] = [:]
    private let automaticCacheTaskLock = NSLock()
    private var automaticCacheTaskRecords: [String: AutomaticCacheTaskRecord] = [:]
    private let activeReaderLeaseLock = NSLock()
    private var activeReaderLeaseRecords: [UUID: ActiveReaderCacheLeaseRecord] = [:]
    private let thumbnailSemaphore = AsyncSemaphore(maxConcurrent: 6)
    private let thumbnailSMBClientSemaphore = AsyncSemaphore(maxConcurrent: 2)
    private let downloadSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbClientSemaphore = AsyncSemaphore(maxConcurrent: 3)
    private let smbConnectionPool = SMBConnectionPool()
    private let webDAVRangeSupportStore = RemoteWebDAVRangeSupportStore()
    private let logger = AppLog.remote
    private let cacheLogger = AppLog.remoteCache

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
        let remoteComicCacheRootURL = (
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
            .appendingPathComponent("JamReader", isDirectory: true)
            .appendingPathComponent("RemoteComics", isDirectory: true)
        self.remoteComicCacheRootURL = remoteComicCacheRootURL
        self.cachePathResolver = RemoteCachePathResolver(
            remoteComicCacheRootURL: remoteComicCacheRootURL
        )
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
        RemoteServerProfileValidator().validate(profile)
    }

    func listDirectory(
        for profile: RemoteServerProfile,
        path: String? = nil
    ) async throws -> [RemoteDirectoryItem] {
        guard validateProfile(profile).allSatisfy({ $0.severity != .error }) else {
            throw RemoteServerBrowsingError.invalidProfile("The remote server profile is incomplete.")
        }

        let requestedPath = normalizeDisplayPath(path ?? profile.normalizedBaseDirectoryPath)
        let logPath = logRemotePath(requestedPath)
        logger.info(
            "Remote directory listing requested provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public)"
        )

        do {
            let items: [RemoteDirectoryItem]
            switch profile.providerKind {
            case .smb:
                items = try await withConnectedSMBClient(for: profile, priority: .userInitiated) { client in
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

                var webDAVItems: [RemoteDirectoryItem] = []
                webDAVItems.reserveCapacity(entries.count)
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

                    webDAVItems.append(
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

                items = webDAVItems
            }

            let comicCount = items.filter { $0.canOpenAsComic }.count
            let directoryCount = items.filter { $0.isDirectory }.count
            logger.info(
                "Remote directory listing completed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public) items=\(items.count) comics=\(comicCount) directories=\(directoryCount)"
            )
            return items
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            logger.error(
                "Remote directory listing failed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
            throw error
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

        let logPath = logRemotePath(reference.path)
        logger.info(
            "Remote comic download requested provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public) forceRefresh=\(forceRefresh)"
        )

        do {
            let result: RemoteComicDownloadResult
            switch profile.providerKind {
            case .smb:
                result = try await withRetry(maxAttempts: 3, baseDelay: 1.0) {
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
                result = try await downloadComicFileCore(
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

            let localPath = AppLogSanitizer.path(result.localFileURL.path)
            logger.info(
                "Remote comic download completed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public) source=\(self.downloadSourceDescription(result.source), privacy: .public) local=\(localPath, privacy: .public)"
            )
            return result
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            logger.error(
                "Remote comic download failed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) path=\(logPath, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
            throw error
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

        logger.info(
            "Remote batch download requested provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) count=\(references.count) forceRefresh=\(forceRefresh)"
        )

        do {
            let outcomes: [RemoteComicBatchDownloadOutcome]
            switch profile.providerKind {
            case .smb:
                outcomes = await concurrentBatchDownloadOutcomes(
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
            case .webdav:
                let authorizationHeader = try resolvedAuthorizationHeader(for: profile)
                outcomes = await concurrentBatchDownloadOutcomes(
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
            }

            let failedCount = outcomes.filter { $0.error != nil }.count
            logger.info(
                "Remote batch download completed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) count=\(outcomes.count) failed=\(failedCount)"
            )
            return outcomes
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            logger.error(
                "Remote batch download failed provider=\(profile.providerKind.rawValue, privacy: .public) server=\(profile.id.uuidString, privacy: .public) count=\(references.count) error=\(errorDescription, privacy: .public)"
            )
            throw error
        }
    }

    func cacheSummary(for profile: RemoteServerProfile? = nil) -> RemoteComicCacheSummary {
        if let profile {
            return cacheRootURLs(for: profile).reduce(.empty) { partial, cacheURL in
                let summary = cacheSummary(forRootURL: cacheURL)
                return RemoteComicCacheSummary(
                    fileCount: partial.fileCount + summary.fileCount,
                    totalBytes: partial.totalBytes + summary.totalBytes,
                    cachedComicBytes: partial.cachedComicBytes + summary.cachedComicBytes,
                    otherCacheBytes: partial.otherCacheBytes + summary.otherCacheBytes
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
        let auxiliaryResources = enumerateOtherCacheResources(in: cacheURL)
        let auxiliaryBytes = auxiliaryResources.reduce(into: Int64.zero) { partialResult, resource in
            partialResult += resource.size
        }
        let totalBytes = DiskUsageScanner.allocatedByteCount(
            at: cacheURL,
            fileManager: fileManager
        )
        let summary = RemoteComicCacheSummary(
            fileCount: resources.count,
            totalBytes: totalBytes > 0 ? totalBytes : resourceBytes,
            cachedComicBytes: resourceBytes,
            otherCacheBytes: auxiliaryBytes
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
        cacheLogger.notice("Remote cache policy preset applying preset=\(preset.rawValue, privacy: .public)")
        cachePolicyStore.savePreset(preset)
        do {
            try trimCacheIfNeeded()
            invalidateCachedSummaries()
            cacheLogger.notice("Remote cache policy preset applied preset=\(preset.rawValue, privacy: .public)")
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            cacheLogger.error(
                "Remote cache policy preset failed preset=\(preset.rawValue, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
            throw error
        }
    }

    func clearCachedComics(for profile: RemoteServerProfile? = nil) throws {
        let scope = cacheScopeDescription(for: profile)
        cacheLogger.notice("Remote cached comics clear requested scope=\(scope, privacy: .public)")
        do {
            cancelAutomaticCacheTasks(forServerID: profile?.id)
            guard !hasActiveReaderLease(forServerID: profile?.id) else {
                cacheLogger.warning(
                    "Remote cached comics clear blocked by active reader lease scope=\(scope, privacy: .public)"
                )
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "Close the active reader before clearing downloaded comics."
                )
            }
            var removedRootCount = 0
            for cacheURL in cacheRootURLs(for: profile) {
                guard fileManager.fileExists(atPath: cacheURL.path) else {
                    continue
                }

                try fileManager.removeItem(at: cacheURL)
                removedRootCount += 1
            }
            invalidateCachedSummaries()
            cacheLogger.notice(
                "Remote cached comics clear completed scope=\(scope, privacy: .public) removedRoots=\(removedRootCount)"
            )
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            cacheLogger.error(
                "Remote cached comics clear failed scope=\(scope, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The downloaded remote comic cache could not be cleared. \(error.userFacingMessage)"
            )
        }
    }

    func clearOtherCachedData(for profile: RemoteServerProfile? = nil) throws {
        let scope = cacheScopeDescription(for: profile)
        cacheLogger.notice("Remote auxiliary cache clear requested scope=\(scope, privacy: .public)")
        do {
            cancelAutomaticCacheTasks(forServerID: profile?.id)
            guard !hasActiveReaderLease(forServerID: profile?.id) else {
                cacheLogger.warning(
                    "Remote auxiliary cache clear blocked by active reader lease scope=\(scope, privacy: .public)"
                )
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "Close the active reader before clearing leftover remote cache data."
                )
            }
            var removedResourceCount = 0
            for cacheURL in cacheRootURLs(for: profile) {
                guard fileManager.fileExists(atPath: cacheURL.path) else {
                    continue
                }

                let auxiliaryResources = enumerateOtherCacheResources(in: cacheURL)
                for resource in auxiliaryResources {
                    guard fileManager.fileExists(atPath: resource.resourceURL.path) else {
                        continue
                    }

                    try fileManager.removeItem(at: resource.resourceURL)
                    removedResourceCount += 1
                    try? removeEmptyParentDirectories(
                        from: resource.resourceURL.deletingLastPathComponent(),
                        stoppingAt: cacheURL
                    )
                }
            }
            invalidateCachedSummaries()
            cacheLogger.notice(
                "Remote auxiliary cache clear completed scope=\(scope, privacy: .public) removedResources=\(removedResourceCount)"
            )
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            cacheLogger.error(
                "Remote auxiliary cache clear failed scope=\(scope, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
            throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                "The leftover remote cache data could not be cleared. \(error.userFacingMessage)"
            )
        }
    }

    func clearCachedComicsForServer(id serverID: UUID) throws {
        let cacheURL = remoteComicCacheRootURL
            .appendingPathComponent(serverID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return
        }

        cacheLogger.notice(
            "Remote cached comics clear requested scope=server:\(serverID.uuidString, privacy: .public)"
        )
        do {
            cancelAutomaticCacheTasks(forServerID: serverID)
            guard !hasActiveReaderLease(forServerID: serverID) else {
                cacheLogger.warning(
                    "Remote cached comics clear blocked by active reader lease scope=server:\(serverID.uuidString, privacy: .public)"
                )
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "Close the active reader before clearing downloaded comics."
                )
            }
            try fileManager.removeItem(at: cacheURL)
            invalidateCachedSummaries()
            cacheLogger.notice(
                "Remote cached comics clear completed scope=server:\(serverID.uuidString, privacy: .public) removedRoots=1"
            )
        } catch {
            let errorDescription = AppLogSanitizer.errorDescription(error)
            cacheLogger.error(
                "Remote cached comics clear failed scope=server:\(serverID.uuidString, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
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

    func registerActiveReaderLease(for reference: RemoteComicFileReference) -> UUID {
        let token = UUID()
        let protectedPaths = Set(allCachedResourceURLs(for: reference).map { $0.standardizedFileURL.path })
        let record = ActiveReaderCacheLeaseRecord(
            serverID: reference.serverID,
            referenceID: reference.id,
            protectedPaths: protectedPaths
        )

        activeReaderLeaseLock.lock()
        activeReaderLeaseRecords[token] = record
        activeReaderLeaseLock.unlock()
        return token
    }

    func unregisterActiveReaderLease(_ token: UUID, for _: RemoteComicFileReference) {
        activeReaderLeaseLock.lock()
        activeReaderLeaseRecords.removeValue(forKey: token)
        activeReaderLeaseLock.unlock()
    }

    func clearCachedComic(for reference: RemoteComicFileReference) throws {
        let logPath = logRemotePath(reference.path)
        cacheLogger.info(
            "Remote cached comic clear requested server=\(reference.serverID.uuidString, privacy: .public) provider=\(reference.providerKind.rawValue, privacy: .public) path=\(logPath, privacy: .public)"
        )
        cancelAutomaticCacheTask(for: reference)
        guard !hasActiveReaderLease(for: reference) else {
            cacheLogger.info(
                "Remote cached comic clear skipped by active reader lease server=\(reference.serverID.uuidString, privacy: .public) provider=\(reference.providerKind.rawValue, privacy: .public) path=\(logPath, privacy: .public)"
            )
            return
        }
        var removedAnyCachedFile = false
        var removedFileCount = 0

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
                removedFileCount += 1
            } catch {
                let errorDescription = AppLogSanitizer.errorDescription(error)
                cacheLogger.error(
                    "Remote cached comic clear failed server=\(reference.serverID.uuidString, privacy: .public) provider=\(reference.providerKind.rawValue, privacy: .public) path=\(logPath, privacy: .public) error=\(errorDescription, privacy: .public)"
                )
                throw RemoteServerBrowsingError.cacheMaintenanceFailed(
                    "The downloaded copy could not be removed from this device. \(error.userFacingMessage)"
                )
            }
        }

        if removedAnyCachedFile {
            invalidateCachedSummaries()
        }
        cacheLogger.info(
            "Remote cached comic clear completed server=\(reference.serverID.uuidString, privacy: .public) provider=\(reference.providerKind.rawValue, privacy: .public) path=\(logPath, privacy: .public) removedFiles=\(removedFileCount)"
        )
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
        if reference.isPDFDocument {
            return nil
        }

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
        guard SupportedComicFormats.isArchiveFileExtension(fileExtension) else {
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

    private func logRemotePath(_ path: String) -> String {
        AppLogSanitizer.path(
            normalizeDisplayPath(path),
            preservingLastComponents: 6
        )
    }

    private func cacheScopeDescription(for profile: RemoteServerProfile?) -> String {
        guard let profile else {
            return "all"
        }

        return "\(profile.providerKind.rawValue):\(profile.id.uuidString)"
    }

    private func downloadSourceDescription(_ source: RemoteComicDownloadResult.Source) -> String {
        switch source {
        case .downloaded:
            return "downloaded"
        case .cachedCurrent:
            return "cachedCurrent"
        case .cachedFallback:
            return "cachedFallback"
        }
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
        cachePathResolver.cachedFileURL(for: reference)
    }

    private func legacyCachedFileURL(for reference: RemoteComicFileReference) -> URL {
        cachePathResolver.legacyCachedFileURL(for: reference)
    }

    private func cachedFileURL(
        for reference: RemoteComicFileReference,
        rootComponents: [String]
    ) -> URL {
        cachePathResolver.cachedFileURL(for: reference, rootComponents: rootComponents)
    }

    private func cachedFileCandidateURLs(for reference: RemoteComicFileReference) -> [URL] {
        cachePathResolver.cachedFileCandidateURLs(for: reference)
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
        RemoteCachePathResolver.legacyCacheRootPathComponents(
            providerKind: providerKind,
            providerRootIdentifier: providerRootIdentifier
        )
    }

    private func cacheRootPathComponents(cacheScopeKey: String) -> [String] {
        RemoteCachePathResolver.cacheRootPathComponents(cacheScopeKey: cacheScopeKey)
    }

    func registerAutomaticCacheTask(
        for reference: RemoteComicFileReference,
        cancellation: @escaping @Sendable () -> Void
    ) {
        automaticCacheTaskLock.lock()
        automaticCacheTaskRecords[reference.id] = AutomaticCacheTaskRecord(
            serverID: reference.serverID,
            cancellation: cancellation
        )
        automaticCacheTaskLock.unlock()
    }

    func unregisterAutomaticCacheTask(for reference: RemoteComicFileReference) {
        automaticCacheTaskLock.lock()
        automaticCacheTaskRecords.removeValue(forKey: reference.id)
        automaticCacheTaskLock.unlock()
    }

    private func cancelAutomaticCacheTask(for reference: RemoteComicFileReference) {
        automaticCacheTaskLock.lock()
        let cancellation = automaticCacheTaskRecords.removeValue(forKey: reference.id)?.cancellation
        automaticCacheTaskLock.unlock()
        cancellation?()
    }

    private func cancelAutomaticCacheTasks(forServerID serverID: UUID?) {
        automaticCacheTaskLock.lock()
        let recordsToCancel: [AutomaticCacheTaskRecord]
        if let serverID {
            let matchingKeys = automaticCacheTaskRecords.compactMap { key, record in
                record.serverID == serverID ? key : nil
            }
            recordsToCancel = matchingKeys.compactMap { automaticCacheTaskRecords.removeValue(forKey: $0) }
        } else {
            recordsToCancel = Array(automaticCacheTaskRecords.values)
            automaticCacheTaskRecords.removeAll()
        }
        automaticCacheTaskLock.unlock()
        recordsToCancel.forEach { $0.cancellation() }
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
        cachePathResolver.cacheRootURL(for: profile)
    }

    private func legacyCacheRootURL(for profile: RemoteServerProfile) -> URL {
        cachePathResolver.legacyCacheRootURL(for: profile)
    }

    private func cacheRootURLs(for profile: RemoteServerProfile?) -> [URL] {
        cachePathResolver.cacheRootURLs(for: profile)
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

    private func hasActiveReaderLease(for reference: RemoteComicFileReference) -> Bool {
        activeReaderLeaseLock.lock()
        let hasLease = activeReaderLeaseRecords.values.contains { record in
            record.referenceID == reference.id
        }
        activeReaderLeaseLock.unlock()
        return hasLease
    }

    private func hasActiveReaderLease(forServerID serverID: UUID?) -> Bool {
        activeReaderLeaseLock.lock()
        let hasLease = activeReaderLeaseRecords.values.contains { record in
            guard let serverID else {
                return true
            }
            return record.serverID == serverID
        }
        activeReaderLeaseLock.unlock()
        return hasLease
    }

    private func isProtectedByActiveReaderLease(_ fileURL: URL) -> Bool {
        let path = fileURL.standardizedFileURL.path
        activeReaderLeaseLock.lock()
        let isProtected = activeReaderLeaseRecords.values.contains { record in
            record.protectedPaths.contains(path)
        }
        activeReaderLeaseLock.unlock()
        return isProtected
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

            guard !isProtectedByActiveReaderLease(candidate.resourceURL) else {
                continue
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

            let size = cachedResourceByteCount(at: resourceURL)
                + cachedMetadataByteCount(for: resourceURL)
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

    private func protectedCachedResourcePaths(in rootURL: URL) -> Set<String> {
        let resources = enumerateCachedComicResources(in: rootURL)
        var protectedPaths = Set<String>()
        protectedPaths.reserveCapacity(resources.count * 2)

        for resource in resources {
            let resourcePath = resource.resourceURL.standardizedFileURL.path
            protectedPaths.insert(resourcePath)

            let metadataPath = cachedMetadataURL(for: resource.resourceURL).standardizedFileURL.path
            if fileManager.fileExists(atPath: metadataPath) {
                protectedPaths.insert(metadataPath)
            }
        }

        return protectedPaths
    }

    private func enumerateOtherCacheResources(in rootURL: URL) -> [AuxiliaryCacheResourceRecord] {
        let protectedPaths = protectedCachedResourcePaths(in: rootURL)

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var resources: [AuxiliaryCacheResourceRecord] = []
        resources.reserveCapacity(32)
        var seenPaths = Set<String>()

        for case let candidateURL as URL in enumerator {
            let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isRegularFile = values?.isRegularFile == true
            let isDirectory = values?.isDirectory == true
            let standardizedPath = candidateURL.standardizedFileURL.path

            if isProtectedCachePath(
                standardizedPath,
                protectedPaths: protectedPaths
            ) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory,
               containsProtectedCachePath(inside: standardizedPath, protectedPaths: protectedPaths) {
                continue
            }

            guard seenPaths.insert(standardizedPath).inserted else {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard isRegularFile || isDirectory else {
                continue
            }

            resources.append(
                AuxiliaryCacheResourceRecord(
                    resourceURL: candidateURL,
                    size: DiskUsageScanner.allocatedByteCount(at: candidateURL, fileManager: fileManager)
                )
            )

            if isDirectory {
                enumerator.skipDescendants()
            }
        }

        return resources
    }

    private func cachedResourceByteCount(at resourceURL: URL) -> Int64 {
        DiskUsageScanner.allocatedByteCount(at: resourceURL, fileManager: fileManager)
    }

    private func cachedMetadataByteCount(for resourceURL: URL) -> Int64 {
        let metadataURL = cachedMetadataURL(for: resourceURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return 0
        }

        return DiskUsageScanner.allocatedByteCount(at: metadataURL, fileManager: fileManager)
    }

    private func isProtectedCachePath(
        _ candidatePath: String,
        protectedPaths: Set<String>
    ) -> Bool {
        for protectedPath in protectedPaths {
            if candidatePath == protectedPath {
                return true
            }

            if candidatePath.hasPrefix(protectedPath + "/") {
                return true
            }
        }

        return false
    }

    private func containsProtectedCachePath(
        inside candidateDirectoryPath: String,
        protectedPaths: Set<String>
    ) -> Bool {
        for protectedPath in protectedPaths where protectedPath.hasPrefix(candidateDirectoryPath + "/") {
            return true
        }

        return false
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

private struct ActiveReaderCacheLeaseRecord {
    let serverID: UUID
    let referenceID: String
    let protectedPaths: Set<String>
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
