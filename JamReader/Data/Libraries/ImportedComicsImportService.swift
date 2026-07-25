import CryptoKit
import Foundation
import os

extension Notification.Name {
    nonisolated static let libraryContentsDidChange = Notification.Name("LibraryContentsDidChange")
}

final class ImportedComicsImportService {
    static let defaultImportedComicsLibraryName = LibraryDescriptor.defaultImportedComicsName
    private static let libraryIDUserInfoKey = "libraryID"

    enum ImportDestinationValidationError: LocalizedError {
        case destinationLibraryNotWritable(String)
        case destinationFolderOutsideLibrary

        var errorDescription: String? {
            switch self {
            case .destinationLibraryNotWritable(let libraryName):
                return String(localized: "\(libraryName) is currently read-only. Choose a writable local library or Imported Comics instead.")
            case .destinationFolderOutsideLibrary:
                return String(localized: "The selected destination folder is no longer available.")
            }
        }
    }

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: any LibraryScanning
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let directoryImageSequenceInspector: DirectoryImageSequenceInspector
    private let fileManager: FileManager
    private let databaseInspector: SQLiteDatabaseInspector
    private let databaseReader: LibraryDatabaseReader
    private let logger = AppLog.libraryImport

    private let supportedComicFileExtensions = SupportedComicFormats.comicFileExtensions
    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: any LibraryScanning,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        directoryImageSequenceInspector: DirectoryImageSequenceInspector = DirectoryImageSequenceInspector(),
        fileManager: FileManager = .default,
        databaseInspector: SQLiteDatabaseInspector = SQLiteDatabaseInspector(),
        databaseReader: LibraryDatabaseReader = LibraryDatabaseReader()
    ) {
        self.store = store
        self.storageManager = storageManager
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.maintenanceStatusStore = maintenanceStatusStore
        self.directoryImageSequenceInspector = directoryImageSequenceInspector
        self.fileManager = fileManager
        self.databaseInspector = databaseInspector
        self.databaseReader = databaseReader
    }

    func importComicResources(
        from urls: [URL],
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        destinationSelection: LibraryImportDestinationSelection = .importedComics,
        destinationRelativePath: String? = nil,
        consumeSourceURLs: Set<URL> = [],
        progressHandler: ((ImportedComicsImportProgress) -> Void)? = nil,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws -> ImportedComicsImportResult {
        try cancellationCheck?()
        var descriptors = try loadNormalizedDescriptors()
        let destinationResolution = try resolveDestinationLibrary(
            in: &descriptors,
            selection: destinationSelection
        )
        try validateImportDestination(destinationResolution.descriptor)
        let destinationAccessSession = try storageManager.makeAccessSession(
            for: destinationResolution.descriptor
        )
        let libraryRootURL = destinationAccessSession.sourceURL.standardizedFileURL
        let destinationDirectoryURL = try importDestinationDirectoryURL(
            libraryRootURL: libraryRootURL,
            relativePath: destinationRelativePath
        )
        let destinationDirectoryPath = AppLogSanitizer.path(destinationDirectoryURL.path)
        let destinationDatabaseURL = storageManager.databaseURL(for: destinationResolution.descriptor)

        var importedComicCount = 0
        var importedDestinationFileURLs: [URL] = []
        var unsupportedItemNames: [String] = []
        var failedItemNames: [String] = []
        let normalizedConsumedSourceURLs = Set(consumeSourceURLs.map(\.standardizedFileURL))
        let transferTotalCount: Int? = traverseDirectories ? nil : urls.count

        do {
            try withExtendedLifetime(destinationAccessSession) {
                try cancellationCheck?()
                if !fileManager.fileExists(atPath: destinationDirectoryURL.path) {
                    try fileManager.createDirectory(
                        at: destinationDirectoryURL,
                        withIntermediateDirectories: true
                    )
                }
                try databaseBootstrapper.ensureDatabaseExists(at: destinationDatabaseURL)

                for url in urls {
                    try cancellationCheck?()
                    try autoreleasepool {
                        try importResource(
                            at: url.standardizedFileURL,
                            into: destinationDirectoryURL,
                            traverseDirectories: traverseDirectories,
                            accessSecurityScopedResources: accessSecurityScopedResources,
                            importedComicCount: &importedComicCount,
                            importedDestinationFileURLs: &importedDestinationFileURLs,
                            unsupportedItemNames: &unsupportedItemNames,
                            failedItemNames: &failedItemNames,
                            consumeSourceURLs: normalizedConsumedSourceURLs,
                            transferTotalCount: transferTotalCount,
                            progressHandler: progressHandler,
                            cancellationCheck: cancellationCheck
                        )
                    }
                }
            }
        } catch is CancellationError {
            if !importedDestinationFileURLs.isEmpty {
                compensateIndexAfterCancellation(
                    importedDestinationFileURLs,
                    for: destinationResolution.descriptor,
                    sourceRootURL: libraryRootURL,
                    databaseURL: destinationDatabaseURL
                )
            }
            throw CancellationError()
        }

        let scanSummary: LibraryScanSummary?
        let scanErrorMessage: String?
        if importedComicCount > 0 {
            do {
                scanSummary = try ensureIndexedLibrary(
                    for: destinationResolution.descriptor,
                    importedFileURLs: importedDestinationFileURLs,
                    progressHandler: progressHandler,
                    cancellationCheck: cancellationCheck
                )
                scanErrorMessage = nil
            } catch is CancellationError {
                if !importedDestinationFileURLs.isEmpty {
                    compensateIndexAfterCancellation(
                        importedDestinationFileURLs,
                        for: destinationResolution.descriptor,
                        sourceRootURL: libraryRootURL,
                        databaseURL: destinationDatabaseURL
                    )
                }
                throw CancellationError()
            } catch {
                let importedFileNames = AppLogSanitizer.namesPreview(
                    importedDestinationFileURLs.map(\.lastPathComponent)
                )
                let errorDescription = AppLogSanitizer.errorDescription(error)
                logger.error(
                    "Automatic indexing failed for library \(destinationResolution.descriptor.id.uuidString, privacy: .public) at \(destinationDirectoryPath, privacy: .public). Imported files: \(importedFileNames, privacy: .public). Error: \(errorDescription, privacy: .public)"
                )
                scanSummary = nil
                scanErrorMessage = error.userFacingMessage
            }
        } else {
            scanSummary = nil
            scanErrorMessage = nil
        }

        return ImportedComicsImportResult(
            importedDestinationID: destinationResolution.descriptor.id,
            importedDestinationName: destinationResolution.descriptor.name,
            importedDestinationDisplayName: destinationResolution.descriptor.displayName,
            createdLibrary: destinationResolution.wasCreated,
            importedComicCount: importedComicCount,
            scanSummary: scanSummary,
            scanErrorMessage: scanErrorMessage,
            unsupportedItemNames: unsupportedItemNames.sorted(),
            failedItemNames: failedItemNames.sorted()
        )
    }

    func importComicResourcesAsync(
        from urls: [URL],
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        destinationSelection: LibraryImportDestinationSelection = .importedComics,
        destinationRelativePath: String? = nil,
        consumeSourceURLs: Set<URL> = [],
        progressHandler: ((ImportedComicsImportProgress) -> Void)? = nil,
        cancellationCheck: (() throws -> Void)? = nil
    ) async throws -> ImportedComicsImportResult {
        let taskCancellationController = LibraryImportCancellationController()
        let combinedCancellationCheck = {
            try taskCancellationController.checkCancelled()
            try cancellationCheck?()
        }

        return try await withTaskCancellationHandler {
            try combinedCancellationCheck()
            let result: ImportedComicsImportResult = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try self.importComicResources(
                            from: urls,
                            traverseDirectories: traverseDirectories,
                            accessSecurityScopedResources: accessSecurityScopedResources,
                            destinationSelection: destinationSelection,
                            destinationRelativePath: destinationRelativePath,
                            consumeSourceURLs: consumeSourceURLs,
                            progressHandler: progressHandler,
                            cancellationCheck: combinedCancellationCheck
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try combinedCancellationCheck()
            return result
        } onCancel: {
            taskCancellationController.cancel()
        }
    }

    func availableDestinationOptions() throws -> [LibraryImportDestinationOption] {
        let descriptors = try loadNormalizedDescriptors()
        let importedComicsRootPath = try storageManager
            .ensureImportedComicsLibraryRootURL()
            .standardizedFileURL
            .path
        let sortedDescriptors = descriptors.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        var options: [LibraryImportDestinationOption] = [
            LibraryImportDestinationOption(
                selection: .importedComics,
                title: String(localized: "Imported Comics"),
                status: .appManaged,
                detail: nil,
                availability: .available
            )
        ]

        options.append(
            contentsOf: sortedDescriptors
                .filter { $0.sourcePath != importedComicsRootPath }
                .map { descriptor in
                    let accessSnapshot = sourceAccessSnapshot(for: descriptor)
                    let availability = importAvailability(for: descriptor, accessSnapshot: accessSnapshot)
                    return LibraryImportDestinationOption(
                        selection: .library(descriptor.id),
                        title: descriptor.displayName,
                        status: importStatus(
                            for: descriptor,
                            accessSnapshot: accessSnapshot,
                            availability: availability
                        ),
                        detail: nil,
                        availability: availability
                    )
                }
        )

        return options
    }

    func clearImportedComicsLibrary() throws {
        logger.notice("Imported comics library clear requested")
        do {
            var descriptors = try loadNormalizedDescriptors()
            let destinationResolution = try ensureImportedComicsLibrary(in: &descriptors)
            let descriptor = destinationResolution.descriptor
            let rootURL = try storageManager.restoreSourceURL(for: descriptor).standardizedFileURL
            let rootPath = AppLogSanitizer.path(rootURL.path)
            var removedItemCount = 0

            if fileManager.fileExists(atPath: rootURL.path) {
                let contents = try fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                )
                removedItemCount = contents.count
                for itemURL in contents {
                    try fileManager.removeItem(at: itemURL)
                }
            } else {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            }

            try storageManager.ensureLibraryMetadataStructure(for: descriptor)
            try databaseBootstrapper.ensureDatabaseExists(
                at: storageManager.databaseURL(for: descriptor)
            )
            _ = try libraryScanner.rescanLibrary(
                sourceRootURL: rootURL,
                databaseURL: storageManager.databaseURL(for: descriptor),
                cancellationCheck: nil,
                progressHandler: nil
            )
            maintenanceStatusStore.clearRecord(for: descriptor.id)
            Self.postLibraryContentsDidChange(for: descriptor.id)
            logger.notice(
                "Imported comics library clear completed libraryID=\(descriptor.id.uuidString, privacy: .public) removedItems=\(removedItemCount) path=\(rootPath, privacy: .public)"
            )
        } catch {
            logger.error(
                "Imported comics library clear failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            throw error
        }
    }

    func importAvailability(for descriptor: LibraryDescriptor) -> LibraryImportDestinationOption.Availability {
        importAvailability(
            for: descriptor,
            accessSnapshot: sourceAccessSnapshot(for: descriptor)
        )
    }

    private func resolveDestinationLibrary(
        in descriptors: inout [LibraryDescriptor],
        selection: LibraryImportDestinationSelection
    ) throws -> (descriptor: LibraryDescriptor, wasCreated: Bool) {
        switch selection {
        case .importedComics:
            return try ensureImportedComicsLibrary(in: &descriptors)
        case .library(let libraryID):
            guard let descriptor = descriptors.first(where: { $0.id == libraryID }) else {
                throw NSError(
                    domain: "LibraryImportDestinationSelection",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "The selected destination library is no longer available.")
                    ]
                )
            }

            return (descriptor, false)
        }
    }

    private func validateImportDestination(_ descriptor: LibraryDescriptor) throws {
        let accessSnapshot = sourceAccessSnapshot(for: descriptor)
        guard accessSnapshot.sourceWritable else {
            throw ImportDestinationValidationError.destinationLibraryNotWritable(descriptor.displayName)
        }
    }

    private func importDestinationDirectoryURL(
        libraryRootURL: URL,
        relativePath: String?
    ) throws -> URL {
        let trimmedPath = relativePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPath.isEmpty else {
            return libraryRootURL
        }

        let destinationURL = libraryRootURL
            .appendingPathComponent(trimmedPath, isDirectory: true)
            .standardizedFileURL
        let resolvedRootPath = libraryRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let resolvedTargetParentPath = destinationURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard resolvedTargetParentPath == resolvedRootPath
                || resolvedTargetParentPath.hasPrefix(resolvedRootPath + "/")
        else {
            throw ImportDestinationValidationError.destinationFolderOutsideLibrary
        }

        return destinationURL
    }

    private func ensureImportedComicsLibrary(
        in descriptors: inout [LibraryDescriptor]
    ) throws -> (descriptor: LibraryDescriptor, wasCreated: Bool) {
        let rootURL = try storageManager
            .ensureImportedComicsLibraryRootURL()
            .standardizedFileURL

        if let existingDescriptorIndex = descriptors.firstIndex(where: {
            $0.kind == .importedComics || $0.sourcePath == rootURL.path
        }) {
            var existingDescriptor = descriptors[existingDescriptorIndex]
            var didChange = false

            if existingDescriptor.kind != .importedComics {
                existingDescriptor.kind = .importedComics
                didChange = true
            }

            if existingDescriptor.sourcePath != rootURL.path {
                existingDescriptor.sourcePath = rootURL.path
                didChange = true
            }

            if !existingDescriptor.sourceBookmarkData.isEmpty {
                existingDescriptor.sourceBookmarkData = Data()
                didChange = true
            }

            if didChange {
                existingDescriptor.updatedAt = Date()
                descriptors[existingDescriptorIndex] = existingDescriptor
                try store.save(descriptors)
            }

            return (existingDescriptor, false)
        }

        let descriptor = try storageManager.registerLibrary(
            at: rootURL,
            suggestedName: Self.defaultImportedComicsLibraryName
        )
        descriptors.append(descriptor)
        do {
            try store.save(descriptors)
        } catch {
            storageManager.deleteLibraryAssets(for: descriptor)
            throw error
        }
        return (descriptor, true)
    }

    private func ensureIndexedLibrary(
        for descriptor: LibraryDescriptor,
        importedFileURLs: [URL],
        progressHandler: ((ImportedComicsImportProgress) -> Void)?,
        cancellationCheck: (() throws -> Void)?
    ) throws -> LibraryScanSummary {
        let databaseURL = storageManager.databaseURL(for: descriptor)
        let accessSession = try storageManager.makeAccessSession(for: descriptor)
        let summary = try withExtendedLifetime(accessSession) {
            try cancellationCheck?()
            try databaseBootstrapper.ensureDatabaseExists(at: databaseURL)
            let libraryRootURL = accessSession.sourceURL.standardizedFileURL
            var seenImportedPaths = Set<String>()
            let normalizedImportedFileURLs = importedFileURLs
                .map(\.standardizedFileURL)
                .filter { fileURL in
                    fileURL.path.hasPrefix(libraryRootURL.path)
                        && seenImportedPaths.insert(fileURL.path).inserted
                }

            let scanSummary: LibraryScanSummary
            if !normalizedImportedFileURLs.isEmpty {
                scanSummary = try libraryScanner.appendImportedComics(
                    sourceRootURL: libraryRootURL,
                    databaseURL: databaseURL,
                    fileURLs: normalizedImportedFileURLs,
                    cancellationCheck: cancellationCheck,
                    progressHandler: { scanProgress in
                        progressHandler?(
                            ImportedComicsImportProgress(
                                phase: .indexing,
                                completedCount: scanProgress.processedComicCount,
                                totalCount: normalizedImportedFileURLs.count,
                                currentItemName: scanProgress.currentPath,
                                scanProgress: scanProgress
                            )
                        )
                    }
                )
            } else {
                scanSummary = try libraryScanner.rescanLibrary(
                    sourceRootURL: libraryRootURL,
                    databaseURL: databaseURL,
                    cancellationCheck: cancellationCheck,
                    progressHandler: { scanProgress in
                        progressHandler?(
                            ImportedComicsImportProgress(
                                phase: .indexing,
                                completedCount: scanProgress.processedComicCount,
                                totalCount: nil,
                                currentItemName: scanProgress.currentPath,
                                scanProgress: scanProgress
                            )
                        )
                    }
                )
            }

            return try validatedIndexedSummary(
                initialSummary: scanSummary,
                descriptor: descriptor,
                sourceRootURL: libraryRootURL,
                databaseURL: databaseURL,
                expectedMinimumComicCount: normalizedImportedFileURLs.isEmpty ? 0 : 1,
                progressHandler: progressHandler,
                cancellationCheck: cancellationCheck
            )
        }
        maintenanceStatusStore.saveRecord(
            LibraryMaintenanceRecord(
                libraryID: descriptor.id,
                title: "Library Updated",
                summary: summary,
                scope: .importIndex,
                contextPath: nil,
                scannedAt: Date()
            )
        )
        Self.postLibraryContentsDidChange(for: descriptor.id)
        return summary
    }

    private func compensateIndexAfterCancellation(
        _ importedFileURLs: [URL],
        for descriptor: LibraryDescriptor,
        sourceRootURL: URL,
        databaseURL: URL
    ) {
        guard !importedFileURLs.isEmpty else {
            return
        }

        do {
            _ = try libraryScanner.appendImportedComics(
                sourceRootURL: sourceRootURL,
                databaseURL: databaseURL,
                fileURLs: importedFileURLs,
                cancellationCheck: nil,
                progressHandler: nil
            )
            Self.postLibraryContentsDidChange(for: descriptor.id)
        } catch {
            let sourcePath = AppLogSanitizer.path(sourceRootURL.path)
            let errorDescription = AppLogSanitizer.errorDescription(error)
            logger.warning(
                "Cancellation compensation indexing failed for library \(descriptor.id.uuidString, privacy: .public) at \(sourcePath, privacy: .public). Error: \(errorDescription, privacy: .public)"
            )
        }
    }

    private func validatedIndexedSummary(
        initialSummary: LibraryScanSummary,
        descriptor: LibraryDescriptor,
        sourceRootURL: URL,
        databaseURL: URL,
        expectedMinimumComicCount: Int,
        progressHandler: ((ImportedComicsImportProgress) -> Void)?,
        cancellationCheck: (() throws -> Void)?
    ) throws -> LibraryScanSummary {
        try cancellationCheck?()

        let currentIndexedComicCount = indexedComicCount(databaseURL: databaseURL)
        if libraryLoadsSuccessfully(databaseURL: databaseURL)
            && currentIndexedComicCount >= expectedMinimumComicCount
        {
            return initialSummary
        }

        let sourcePath = AppLogSanitizer.path(sourceRootURL.path)
        logger.warning(
            "Imported comics validation requested recovery for library \(descriptor.id.uuidString, privacy: .public). Expected comics >= \(expectedMinimumComicCount), current indexed comics=\(currentIndexedComicCount), sourceRoot=\(sourcePath, privacy: .public)"
        )

        try databaseBootstrapper.ensureDatabaseExists(at: databaseURL)
        let recoverySummary = try libraryScanner.scanLibrary(
            sourceRootURL: sourceRootURL,
            databaseURL: databaseURL,
            cancellationCheck: cancellationCheck,
            progressHandler: { scanProgress in
                progressHandler?(
                    ImportedComicsImportProgress(
                        phase: .indexing,
                        completedCount: scanProgress.processedComicCount,
                        totalCount: nil,
                        currentItemName: scanProgress.currentPath,
                        scanProgress: scanProgress
                    )
                )
            }
        )

        let recoveredComicCount = indexedComicCount(databaseURL: databaseURL)
        guard libraryLoadsSuccessfully(databaseURL: databaseURL),
              recoveredComicCount >= expectedMinimumComicCount
        else {
            let summary = databaseInspector.inspectDatabase(at: databaseURL)
            logger.error(
                "Imported comics recovery scan did not index expected content for library \(descriptor.id.uuidString, privacy: .public). Summary exists=\(summary.exists) folders=\(summary.folderCount) comics=\(summary.comicCount) sourceRoot=\(sourcePath, privacy: .public)"
            )
            throw NSError(
                domain: "ImportedComicsImportService",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        summary.lastError
                        ?? String(localized: "Imported files were copied into \(descriptor.displayName), but the local library index could not be opened.")
                ]
            )
        }

        return recoverySummary
    }

    private func libraryLoadsSuccessfully(databaseURL: URL) -> Bool {
        let summary = databaseInspector.inspectDatabase(at: databaseURL)
        guard summary.exists else {
            return false
        }

        do {
            _ = try databaseReader.loadFolderContent(databaseURL: databaseURL, folderID: 1)
            return true
        } catch {
            logger.warning(
                "Imported comics library health check failed database=\(AppLogSanitizer.path(databaseURL.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return false
        }
    }

    private func indexedComicCount(databaseURL: URL) -> Int {
        databaseInspector.inspectDatabase(at: databaseURL).comicCount
    }

    private static func postLibraryContentsDidChange(for libraryID: UUID) {
        NotificationCenter.default.post(
            name: .libraryContentsDidChange,
            object: nil,
            userInfo: [libraryIDUserInfoKey: libraryID]
        )
    }

    private func importAvailability(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot
    ) -> LibraryImportDestinationOption.Availability {
        if !accessSnapshot.sourceWritable {
            return .unavailable(
                String(localized: "This source folder is read-only on this device. Reading and local metadata stay available, but importing files here is disabled.")
            )
        }

        return .available
    }

    private func importStatus(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot,
        availability: LibraryImportDestinationOption.Availability
    ) -> LibraryImportDestinationOption.Status? {
        if descriptor.kind.isManagedByApp {
            return .appManaged
        }

        switch availability {
        case .available:
            return .linkedFolder
        case .unavailable:
            if !accessSnapshot.sourceWritable {
                return .readOnly
            }

            return nil
        }
    }

    private func sourceAccessSnapshot(for descriptor: LibraryDescriptor) -> LibraryAccessSnapshot {
        storageManager.accessSnapshot(
            for: descriptor,
            inspector: databaseInspector
        )
    }

    private func loadNormalizedDescriptors() throws -> [LibraryDescriptor] {
        let descriptors = try store.load()
        let normalizedDescriptors = storageManager.normalizeDescriptors(descriptors)
        if normalizedDescriptors != descriptors {
            try store.save(normalizedDescriptors)
        }
        return normalizedDescriptors
    }

    private func importResource(
        at sourceURL: URL,
        into destinationDirectoryURL: URL,
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        importedComicCount: inout Int,
        importedDestinationFileURLs: inout [URL],
        unsupportedItemNames: inout [String],
        failedItemNames: inout [String],
        consumeSourceURLs: Set<URL>,
        transferTotalCount: Int?,
        progressHandler: ((ImportedComicsImportProgress) -> Void)?,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        let scopedAccess = accessSecurityScopedResources
            ? sourceURL.startAccessingSecurityScopedResource()
            : false
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        } catch {
            failedItemNames.append(sourceURL.lastPathComponent)
            return
        }

        if values.isDirectory == true {
            if let inspection = try? directoryImageSequenceInspector.inspectComicDirectory(at: sourceURL) {
                do {
                    try cancellationCheck?()
                    try importComicDirectory(
                        at: sourceURL,
                        inspection: inspection,
                        into: destinationDirectoryURL,
                        importedComicCount: &importedComicCount,
                        importedDestinationFileURLs: &importedDestinationFileURLs,
                        failedItemNames: &failedItemNames,
                        consumeSourceURLs: consumeSourceURLs,
                        transferTotalCount: transferTotalCount,
                        progressHandler: progressHandler,
                        cancellationCheck: cancellationCheck
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedItemNames.append(sourceURL.lastPathComponent)
                }
                return
            }

            guard traverseDirectories else {
                unsupportedItemNames.append(sourceURL.lastPathComponent)
                return
            }

            try cancellationCheck?()

            try importDirectoryContents(
                at: sourceURL,
                into: destinationDirectoryURL,
                importedComicCount: &importedComicCount,
                importedDestinationFileURLs: &importedDestinationFileURLs,
                unsupportedItemNames: &unsupportedItemNames,
                failedItemNames: &failedItemNames,
                consumeSourceURLs: consumeSourceURLs,
                transferTotalCount: transferTotalCount,
                progressHandler: progressHandler,
                cancellationCheck: cancellationCheck
            )
            return
        }

        guard values.isRegularFile == true else {
            unsupportedItemNames.append(sourceURL.lastPathComponent)
            return
        }

        guard supportsComicFile(at: sourceURL) else {
            unsupportedItemNames.append(sourceURL.lastPathComponent)
            return
        }

        do {
            try cancellationCheck?()
            let destinationPlan = try importDestinationPlan(
                for: sourceURL,
                in: destinationDirectoryURL,
                cancellationCheck: cancellationCheck
            )
            if destinationPlan.requiresTransfer {
                try transferImportedResource(
                    at: sourceURL,
                    to: destinationPlan.destinationURL,
                    consumeSourceURLs: consumeSourceURLs
                )
            }
            let destinationURL = destinationPlan.destinationURL
            importedDestinationFileURLs.append(destinationURL)
            importedComicCount += 1
            progressHandler?(
                ImportedComicsImportProgress(
                    phase: .transferring,
                    completedCount: importedComicCount,
                    totalCount: transferTotalCount,
                    currentItemName: sourceURL.lastPathComponent,
                    scanProgress: nil
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            failedItemNames.append(sourceURL.lastPathComponent)
        }
    }

    private func importDirectoryContents(
        at directoryURL: URL,
        into destinationDirectoryURL: URL,
        importedComicCount: inout Int,
        importedDestinationFileURLs: inout [URL],
        unsupportedItemNames: inout [String],
        failedItemNames: inout [String],
        consumeSourceURLs: Set<URL>,
        transferTotalCount: Int?,
        progressHandler: ((ImportedComicsImportProgress) -> Void)?,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            failedItemNames.append(directoryURL.lastPathComponent)
            return
        }

        var discoveredAnyComic = false

        for case let candidateURL as URL in enumerator {
            try cancellationCheck?()

            var shouldSkipDescendants = false
            try autoreleasepool {
                let values = try? candidateURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    if let inspection = try? directoryImageSequenceInspector.inspectComicDirectory(at: candidateURL) {
                        discoveredAnyComic = true
                        shouldSkipDescendants = true

                        do {
                            try cancellationCheck?()
                            try importComicDirectory(
                                at: candidateURL,
                                inspection: inspection,
                                into: destinationDirectoryURL,
                                importedComicCount: &importedComicCount,
                                importedDestinationFileURLs: &importedDestinationFileURLs,
                                failedItemNames: &failedItemNames,
                                consumeSourceURLs: consumeSourceURLs,
                                transferTotalCount: transferTotalCount,
                                progressHandler: progressHandler,
                                cancellationCheck: cancellationCheck
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            failedItemNames.append(candidateURL.lastPathComponent)
                        }
                    }
                    return
                }

                guard values?.isRegularFile == true, supportsComicFile(at: candidateURL) else {
                    return
                }

                discoveredAnyComic = true

                do {
                    try cancellationCheck?()
                    let destinationPlan = try importDestinationPlan(
                        for: candidateURL,
                        in: destinationDirectoryURL,
                        cancellationCheck: cancellationCheck
                    )
                    if destinationPlan.requiresTransfer {
                        try transferImportedResource(
                            at: candidateURL,
                            to: destinationPlan.destinationURL,
                            consumeSourceURLs: consumeSourceURLs
                        )
                    }
                    let destinationURL = destinationPlan.destinationURL
                    importedDestinationFileURLs.append(destinationURL)
                    importedComicCount += 1
                    progressHandler?(
                        ImportedComicsImportProgress(
                            phase: .transferring,
                            completedCount: importedComicCount,
                            totalCount: transferTotalCount,
                            currentItemName: candidateURL.lastPathComponent,
                            scanProgress: nil
                        )
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedItemNames.append(candidateURL.lastPathComponent)
                }
            }

            if shouldSkipDescendants {
                enumerator.skipDescendants()
            }
        }

        if !discoveredAnyComic {
            unsupportedItemNames.append(directoryURL.lastPathComponent)
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard !fileManager.fileExists(atPath: preferredURL.path) else {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let fileExtension = sourceURL.pathExtension
            var counter = 1

            while true {
                let candidateName: String
                if fileExtension.isEmpty {
                    candidateName = "\(baseName) (\(counter))"
                } else {
                    candidateName = "\(baseName) (\(counter)).\(fileExtension)"
                }

                let candidateURL = directoryURL.appendingPathComponent(candidateName)
                if !fileManager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }

                counter += 1
            }
        }

        return preferredURL
    }

    private func importComicDirectory(
        at sourceDirectoryURL: URL,
        inspection: DirectoryImageSequenceInspection,
        into destinationDirectoryURL: URL,
        importedComicCount: inout Int,
        importedDestinationFileURLs: inout [URL],
        failedItemNames: inout [String],
        consumeSourceURLs: Set<URL>,
        transferTotalCount: Int?,
        progressHandler: ((ImportedComicsImportProgress) -> Void)?,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        try cancellationCheck?()
        let destinationPlan = try directoryImportDestinationPlan(
            for: sourceDirectoryURL,
            inspection: inspection,
            in: destinationDirectoryURL,
            cancellationCheck: cancellationCheck
        )
        if destinationPlan.requiresTransfer {
            try transferImportedResource(
                at: sourceDirectoryURL,
                to: destinationPlan.destinationURL,
                consumeSourceURLs: consumeSourceURLs
            )
        }

        importedDestinationFileURLs.append(destinationPlan.destinationURL)
        importedComicCount += 1
        progressHandler?(
            ImportedComicsImportProgress(
                phase: .transferring,
                completedCount: importedComicCount,
                totalCount: transferTotalCount,
                currentItemName: sourceDirectoryURL.lastPathComponent,
                scanProgress: nil
            )
        )
    }

    private func importDestinationPlan(
        for sourceURL: URL,
        in directoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> (destinationURL: URL, requiresTransfer: Bool) {
        try cancellationCheck?()
        let preferredURL = directoryURL
            .appendingPathComponent(sourceURL.lastPathComponent)
            .standardizedFileURL
        if fileManager.fileExists(atPath: preferredURL.path),
           try filesAppearEquivalent(
            sourceURL.standardizedFileURL,
            preferredURL,
            cancellationCheck: cancellationCheck
           ) {
            try cleanupEquivalentDuplicateCopies(
                for: sourceURL.standardizedFileURL,
                keeping: preferredURL,
                in: directoryURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            )
            return (preferredURL, false)
        }

        if let existingEquivalentURL = try existingEquivalentDestination(
            for: sourceURL.standardizedFileURL,
            in: directoryURL.standardizedFileURL,
            cancellationCheck: cancellationCheck
        ) {
            try cleanupEquivalentDuplicateCopies(
                for: sourceURL.standardizedFileURL,
                keeping: existingEquivalentURL,
                in: directoryURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            )
            return (existingEquivalentURL, false)
        }

        return (uniqueDestinationURL(for: sourceURL, in: directoryURL).standardizedFileURL, true)
    }

    private func directoryImportDestinationPlan(
        for sourceDirectoryURL: URL,
        inspection: DirectoryImageSequenceInspection,
        in destinationDirectoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> (destinationURL: URL, requiresTransfer: Bool) {
        try cancellationCheck?()
        let preferredURL = destinationDirectoryURL
            .appendingPathComponent(sourceDirectoryURL.lastPathComponent, isDirectory: true)
            .standardizedFileURL

        if fileManager.fileExists(atPath: preferredURL.path),
           try directoriesAppearEquivalent(
            sourceDirectoryURL.standardizedFileURL,
            sourceInspection: inspection,
            preferredURL,
            cancellationCheck: cancellationCheck
           ) {
            try cleanupEquivalentDuplicateComicDirectories(
                for: sourceDirectoryURL.standardizedFileURL,
                sourceInspection: inspection,
                keeping: preferredURL,
                in: destinationDirectoryURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            )
            return (preferredURL, false)
        }

        if let existingEquivalentURL = try existingEquivalentComicDirectory(
            for: sourceDirectoryURL.standardizedFileURL,
            sourceInspection: inspection,
            in: destinationDirectoryURL.standardizedFileURL,
            cancellationCheck: cancellationCheck
        ) {
            try cleanupEquivalentDuplicateComicDirectories(
                for: sourceDirectoryURL.standardizedFileURL,
                sourceInspection: inspection,
                keeping: existingEquivalentURL,
                in: destinationDirectoryURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            )
            return (existingEquivalentURL, false)
        }

        return (
            uniqueDestinationURL(for: sourceDirectoryURL, in: destinationDirectoryURL).standardizedFileURL,
            true
        )
    }

    private func existingEquivalentDestination(
        for sourceURL: URL,
        in directoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> URL? {
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
            try cancellationCheck?()
            let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            if try filesAppearEquivalent(
                sourceURL,
                candidateURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            ) {
                return candidateURL.standardizedFileURL
            }
        }

        return nil
    }

    private func existingEquivalentComicDirectory(
        for sourceDirectoryURL: URL,
        sourceInspection: DirectoryImageSequenceInspection,
        in destinationDirectoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> URL? {
        let candidates = try fileManager.contentsOfDirectory(
            at: destinationDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
            try cancellationCheck?()
            let values = try? candidateURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else {
                continue
            }

            if try directoriesAppearEquivalent(
                sourceDirectoryURL,
                sourceInspection: sourceInspection,
                candidateURL.standardizedFileURL,
                cancellationCheck: cancellationCheck
            ) {
                return candidateURL.standardizedFileURL
            }
        }

        return nil
    }

    private func cleanupEquivalentDuplicateCopies(
        for sourceURL: URL,
        keeping canonicalURL: URL,
        in directoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
            try cancellationCheck?()
            let normalizedCandidateURL = candidateURL.standardizedFileURL
            guard normalizedCandidateURL != canonicalURL else {
                continue
            }

            let values = try? normalizedCandidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true,
                  isRetryDuplicateName(
                    normalizedCandidateURL.lastPathComponent,
                    for: sourceURL.lastPathComponent
                  ),
                  try filesAppearEquivalent(
                    canonicalURL,
                    normalizedCandidateURL,
                    cancellationCheck: cancellationCheck
                  )
            else {
                continue
            }

            removeCleanupItemIfPossible(
                at: normalizedCandidateURL,
                reason: "duplicateFileCopy"
            )
        }
    }

    private func cleanupEquivalentDuplicateComicDirectories(
        for sourceDirectoryURL: URL,
        sourceInspection: DirectoryImageSequenceInspection,
        keeping canonicalURL: URL,
        in destinationDirectoryURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: destinationDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
            try cancellationCheck?()
            let normalizedCandidateURL = candidateURL.standardizedFileURL
            guard normalizedCandidateURL != canonicalURL else {
                continue
            }

            let values = try? normalizedCandidateURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true,
                  isRetryDuplicateName(
                    normalizedCandidateURL.lastPathComponent,
                    for: sourceDirectoryURL.lastPathComponent
                  ),
                  try directoriesAppearEquivalent(
                    sourceDirectoryURL,
                    sourceInspection: sourceInspection,
                    normalizedCandidateURL,
                    cancellationCheck: cancellationCheck
                  )
            else {
                continue
            }

            removeCleanupItemIfPossible(
                at: normalizedCandidateURL,
                reason: "duplicateDirectoryCopy"
            )
        }
    }

    private func isRetryDuplicateName(_ candidateName: String, for originalName: String) -> Bool {
        let originalURL = URL(fileURLWithPath: originalName)
        let candidateURL = URL(fileURLWithPath: candidateName)

        guard candidateURL.pathExtension.caseInsensitiveCompare(originalURL.pathExtension) == .orderedSame else {
            return false
        }

        let originalBaseName = originalURL.deletingPathExtension().lastPathComponent
        let candidateBaseName = candidateURL.deletingPathExtension().lastPathComponent
        let prefix = "\(originalBaseName) ("

        guard candidateBaseName.hasPrefix(prefix), candidateBaseName.hasSuffix(")") else {
            return false
        }

        let numberText = String(
            candidateBaseName
                .dropFirst(prefix.count)
                .dropLast()
        )
        return Int(numberText) != nil
    }

    private func filesAppearEquivalent(
        _ lhs: URL,
        _ rhs: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> Bool {
        try cancellationCheck?()
        if lhs.standardizedFileURL == rhs.standardizedFileURL {
            return true
        }

        let lhsSize = try fileSize(for: lhs)
        let rhsSize = try fileSize(for: rhs)
        guard lhsSize == rhsSize else {
            return false
        }

        return try Self.importFingerprint(for: lhs, cancellationCheck: cancellationCheck)
            == Self.importFingerprint(for: rhs, cancellationCheck: cancellationCheck)
    }

    private func directoriesAppearEquivalent(
        _ lhs: URL,
        sourceInspection: DirectoryImageSequenceInspection,
        _ rhs: URL,
        cancellationCheck: (() throws -> Void)?
    ) throws -> Bool {
        try cancellationCheck?()
        if lhs.standardizedFileURL == rhs.standardizedFileURL {
            return true
        }

        guard let rhsInspection = try directoryImageSequenceInspector.inspectComicDirectory(at: rhs) else {
            return false
        }

        try cancellationCheck?()
        let sourceFingerprint = try directoryImageSequenceInspector.fingerprint(for: sourceInspection)
        try cancellationCheck?()
        let destinationFingerprint = try directoryImageSequenceInspector.fingerprint(for: rhsInspection)
        try cancellationCheck?()
        return sourceFingerprint == destinationFingerprint
    }

    private func fileSize(for url: URL) throws -> Int64 {
        Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func importFingerprint(
        for fileURL: URL,
        chunkSize: Int = 1_048_576,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws -> String {
        precondition(chunkSize > 0)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var digest = SHA256()
        while true {
            try cancellationCheck?()
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty {
                break
            }
            digest.update(data: data)
        }
        try cancellationCheck?()
        let finalizedDigest = digest.finalize()
        return finalizedDigest.map { String(format: "%02x", $0) }.joined()
    }

    private func transferImportedResource(
        at sourceURL: URL,
        to destinationURL: URL,
        consumeSourceURLs: Set<URL>
    ) throws {
        let normalizedSourceURL = sourceURL.standardizedFileURL
        if consumeSourceURLs.contains(normalizedSourceURL) {
            do {
                try fileManager.moveItem(at: normalizedSourceURL, to: destinationURL)
                return
            } catch {
                try fileManager.copyItem(at: normalizedSourceURL, to: destinationURL)
                removeCleanupItemIfPossible(
                    at: normalizedSourceURL,
                    reason: "consumedSourceAfterCopy"
                )
                return
            }
        }

        try fileManager.copyItem(at: normalizedSourceURL, to: destinationURL)
    }

    private func removeCleanupItemIfPossible(at url: URL, reason: String) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            logger.warning(
                "Imported comics cleanup remove failed reason=\(reason, privacy: .public) path=\(AppLogSanitizer.path(url.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }

    private func supportsComicFile(at url: URL) -> Bool {
        supportedComicFileExtensions.contains(url.pathExtension.lowercased())
    }
}
