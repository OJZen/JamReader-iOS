import CryptoKit
import Foundation

struct ImportedComicsImportResult {
    let importedDestinationID: UUID
    let importedDestinationName: String
    let createdLibrary: Bool
    let importedComicCount: Int
    let scanSummary: LibraryScanSummary?
    let scanErrorMessage: String?
    let unsupportedItemNames: [String]
    let failedItemNames: [String]

    var hasImportedAnyComics: Bool {
        importedComicCount > 0
    }

    func completionMessageLines(extraFailedItemNames: [String] = []) -> [String] {
        var messageLines: [String] = []

        if createdLibrary {
            messageLines.append("Added \(importedDestinationName).")
        }

        if importedComicCount > 0 {
            let comicWord = importedComicCount == 1 ? "comic file" : "comic files"
            messageLines.append("Imported \(importedComicCount) \(comicWord) into \(importedDestinationName).")
        }

        if let scanSummary {
            messageLines.append(scanSummary.indexedSummaryLine + ".")
        } else if let scanErrorMessage {
            messageLines.append("Automatic indexing failed: \(scanErrorMessage)")
            messageLines.append("Open \(importedDestinationName) and run Refresh to index the new files.")
        }

        if !unsupportedItemNames.isEmpty {
            let itemWord = unsupportedItemNames.count == 1 ? "item" : "items"
            messageLines.append("Skipped \(unsupportedItemNames.count) unsupported \(itemWord).")
        }

        let combinedFailedItemNames = failedItemNames + extraFailedItemNames
        if !combinedFailedItemNames.isEmpty {
            let preview = Self.previewList(from: combinedFailedItemNames)
            messageLines.append("Failed to import \(combinedFailedItemNames.count) item(s): \(preview).")
        }

        return messageLines
    }

    private static func previewList(from names: [String], limit: Int = 3) -> String {
        let uniqueSortedNames = Array(Set(names)).sorted()
        guard uniqueSortedNames.count > limit else {
            return uniqueSortedNames.joined(separator: ", ")
        }

        let preview = uniqueSortedNames.prefix(limit).joined(separator: ", ")
        return "\(preview), +\(uniqueSortedNames.count - limit) more"
    }
}

struct ImportedComicsImportProgress {
    enum Phase: Equatable {
        case transferring
        case indexing
    }

    let phase: Phase
    let completedCount: Int
    let totalCount: Int?
    let currentItemName: String?
    let scanProgress: LibraryScanProgress?
}

final class ImportedComicsImportService {
    enum ImportDestinationValidationError: LocalizedError {
        case destinationLibraryNotWritable(String)

        var errorDescription: String? {
            switch self {
            case .destinationLibraryNotWritable(let libraryName):
                return "\(libraryName) is currently read-only. Choose a writable local library or Imported Comics instead."
            }
        }
    }

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: LibraryScanner
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let fileManager: FileManager

    private let supportedComicFileExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf"
    ]
    private let importedComicsLibraryName = "Imported Comics"

    init(
        store: LibraryDescriptorStore,
        storageManager: LibraryStorageManager,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: LibraryScanner,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.storageManager = storageManager
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.maintenanceStatusStore = maintenanceStatusStore
        self.fileManager = fileManager
    }

    func importComicResources(
        from urls: [URL],
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        destinationSelection: LibraryImportDestinationSelection = .importedComics,
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
        let destinationDirectoryURL = destinationAccessSession.sourceURL.standardizedFileURL

        var importedComicCount = 0
        var importedDestinationFileURLs: [URL] = []
        var unsupportedItemNames: [String] = []
        var failedItemNames: [String] = []
        let normalizedConsumedSourceURLs = Set(consumeSourceURLs.map(\.standardizedFileURL))
        let transferTotalCount: Int? = traverseDirectories ? nil : urls.count

        try withExtendedLifetime(destinationAccessSession) {
            try cancellationCheck?()
            if !fileManager.fileExists(atPath: destinationDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: destinationDirectoryURL,
                    withIntermediateDirectories: true
                )
            }

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
                throw CancellationError()
            } catch {
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
        consumeSourceURLs: Set<URL> = [],
        progressHandler: ((ImportedComicsImportProgress) -> Void)? = nil,
        cancellationCheck: (() throws -> Void)? = nil
    ) async throws -> ImportedComicsImportResult {
        try cancellationCheck?()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.importComicResources(
                        from: urls,
                        traverseDirectories: traverseDirectories,
                        accessSecurityScopedResources: accessSecurityScopedResources,
                        destinationSelection: destinationSelection,
                        consumeSourceURLs: consumeSourceURLs,
                        progressHandler: progressHandler,
                        cancellationCheck: cancellationCheck
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func availableDestinationOptions() throws -> [LibraryImportDestinationOption] {
        let descriptors = try loadNormalizedDescriptors()
        let importedComicsRootPath = try storageManager
            .ensureImportedComicsLibraryRootURL()
            .standardizedFileURL
            .path
        let sortedDescriptors = descriptors.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        var options: [LibraryImportDestinationOption] = [
            LibraryImportDestinationOption(
                selection: .importedComics,
                title: importedComicsLibraryName,
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
                    title: descriptor.name,
                    status: importStatus(
                        for: descriptor,
                        accessSnapshot: accessSnapshot,
                        availability: availability
                    ),
                    detail: descriptor.sourcePath,
                    availability: availability
                )
            }
        )

        return options
    }

    func clearImportedComicsLibrary() throws {
        var descriptors = try loadNormalizedDescriptors()
        let destinationResolution = try ensureImportedComicsLibrary(in: &descriptors)
        let descriptor = destinationResolution.descriptor
        let rootURL = try storageManager.restoreSourceURL(for: descriptor).standardizedFileURL

        if fileManager.fileExists(atPath: rootURL.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )
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
            databaseURL: storageManager.databaseURL(for: descriptor)
        )
        maintenanceStatusStore.clearRecord(for: descriptor.id)
    }

    func importAvailability(for descriptor: LibraryDescriptor) -> LibraryImportDestinationOption.Availability {
        importAvailability(
            for: descriptor,
            accessSnapshot: sourceAccessSnapshot(for: descriptor)
        )
    }

    private func resolveDestinationLibrary(
        in descriptors: inout [LibraryDescriptor]
        ,
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
                        NSLocalizedDescriptionKey: "The selected destination library is no longer available."
                    ]
                )
            }

            return (descriptor, false)
        }
    }

    private func validateImportDestination(_ descriptor: LibraryDescriptor) throws {
        let accessSnapshot = sourceAccessSnapshot(for: descriptor)
        guard accessSnapshot.sourceWritable else {
            throw ImportDestinationValidationError.destinationLibraryNotWritable(descriptor.name)
        }
    }

    private func ensureImportedComicsLibrary(
        in descriptors: inout [LibraryDescriptor]
    ) throws -> (descriptor: LibraryDescriptor, wasCreated: Bool) {
        let rootURL = try storageManager
            .ensureImportedComicsLibraryRootURL()
            .standardizedFileURL

        if let existingDescriptor = descriptors.first(where: { $0.sourcePath == rootURL.path }) {
            return (existingDescriptor, false)
        }

        let descriptor = try storageManager.registerLibrary(
            at: rootURL,
            suggestedName: importedComicsLibraryName
        )
        descriptors.append(descriptor)
        try store.save(descriptors)
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

            if !normalizedImportedFileURLs.isEmpty {
                return try libraryScanner.appendImportedComics(
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
            }

            return try libraryScanner.rescanLibrary(
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
        return summary
    }

    private func importAvailability(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot
    ) -> LibraryImportDestinationOption.Availability {
        if !accessSnapshot.sourceWritable {
            return .unavailable(
                "This source folder is read-only on this device. Reading and local metadata stay available, but importing files here is disabled."
            )
        }

        return .available
    }

    private func importStatus(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot,
        availability: LibraryImportDestinationOption.Availability
    ) -> LibraryImportDestinationOption.Status? {
        if descriptor.kind == .importedComics {
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
            inspector: SQLiteDatabaseInspector()
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
                in: destinationDirectoryURL
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

            autoreleasepool {
                let values = try? candidateURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
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
                        in: destinationDirectoryURL
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
                } catch {
                    failedItemNames.append(candidateURL.lastPathComponent)
                }
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

    private func importDestinationPlan(
        for sourceURL: URL,
        in directoryURL: URL
    ) throws -> (destinationURL: URL, requiresTransfer: Bool) {
        let preferredURL = directoryURL
            .appendingPathComponent(sourceURL.lastPathComponent)
            .standardizedFileURL
        if fileManager.fileExists(atPath: preferredURL.path),
           try filesAppearEquivalent(sourceURL.standardizedFileURL, preferredURL) {
            try cleanupEquivalentDuplicateCopies(
                for: sourceURL.standardizedFileURL,
                keeping: preferredURL,
                in: directoryURL.standardizedFileURL
            )
            return (preferredURL, false)
        }

        if let existingEquivalentURL = try existingEquivalentDestination(
            for: sourceURL.standardizedFileURL,
            in: directoryURL.standardizedFileURL
        ) {
            try cleanupEquivalentDuplicateCopies(
                for: sourceURL.standardizedFileURL,
                keeping: existingEquivalentURL,
                in: directoryURL.standardizedFileURL
            )
            return (existingEquivalentURL, false)
        }

        return (uniqueDestinationURL(for: sourceURL, in: directoryURL).standardizedFileURL, true)
    }

    private func existingEquivalentDestination(
        for sourceURL: URL,
        in directoryURL: URL
    ) throws -> URL? {
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
            let values = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            if try filesAppearEquivalent(sourceURL, candidateURL.standardizedFileURL) {
                return candidateURL.standardizedFileURL
            }
        }

        return nil
    }

    private func cleanupEquivalentDuplicateCopies(
        for sourceURL: URL,
        keeping canonicalURL: URL,
        in directoryURL: URL
    ) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for candidateURL in candidates {
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
                  try filesAppearEquivalent(canonicalURL, normalizedCandidateURL)
            else {
                continue
            }

            try? fileManager.removeItem(at: normalizedCandidateURL)
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

    private func filesAppearEquivalent(_ lhs: URL, _ rhs: URL) throws -> Bool {
        if lhs.standardizedFileURL == rhs.standardizedFileURL {
            return true
        }

        let lhsSize = try fileSize(for: lhs)
        let rhsSize = try fileSize(for: rhs)
        guard lhsSize == rhsSize else {
            return false
        }

        return try importFingerprint(for: lhs) == importFingerprint(for: rhs)
    }

    private func fileSize(for url: URL) throws -> Int64 {
        Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func importFingerprint(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty {
                break
            }
            digest.update(data: data)
        }
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
                try? fileManager.removeItem(at: normalizedSourceURL)
                return
            }
        }

        try fileManager.copyItem(at: normalizedSourceURL, to: destinationURL)
    }

    private func supportsComicFile(at url: URL) -> Bool {
        supportedComicFileExtensions.contains(url.pathExtension.lowercased())
    }
}
