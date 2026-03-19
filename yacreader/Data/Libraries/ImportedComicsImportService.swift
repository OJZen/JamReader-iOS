import Foundation

struct ImportedComicsImportResult {
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

final class ImportedComicsImportService {
    enum ImportDestinationValidationError: LocalizedError {
        case destinationLibraryNotWritable(String)
        case destinationLibraryMirrored(String)

        var errorDescription: String? {
            switch self {
            case .destinationLibraryNotWritable(let libraryName):
                return "\(libraryName) is currently read-only. Choose a writable local library or Imported Comics instead."
            case .destinationLibraryMirrored(let libraryName):
                return "\(libraryName) is mirrored from an external source and is kept compatible for browsing. Import new comics into a writable in-place library instead."
            }
        }
    }

    private let store: LibraryDescriptorStore
    private let storageManager: LibraryStorageManager
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: LibraryScanner
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
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.storageManager = storageManager
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.fileManager = fileManager
    }

    func importComicResources(
        from urls: [URL],
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) throws -> ImportedComicsImportResult {
        var descriptors = try store.load()
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
        var unsupportedItemNames: [String] = []
        var failedItemNames: [String] = []

        try withExtendedLifetime(destinationAccessSession) {
            if !fileManager.fileExists(atPath: destinationDirectoryURL.path) {
                try fileManager.createDirectory(
                    at: destinationDirectoryURL,
                    withIntermediateDirectories: true
                )
            }

            for url in urls {
                try importResource(
                    at: url.standardizedFileURL,
                    into: destinationDirectoryURL,
                    traverseDirectories: traverseDirectories,
                    accessSecurityScopedResources: accessSecurityScopedResources,
                    importedComicCount: &importedComicCount,
                    unsupportedItemNames: &unsupportedItemNames,
                    failedItemNames: &failedItemNames
                )
            }
        }

        let scanSummary: LibraryScanSummary?
        let scanErrorMessage: String?
        if importedComicCount > 0 {
            do {
                scanSummary = try ensureIndexedLibrary(for: destinationResolution.descriptor)
                scanErrorMessage = nil
            } catch {
                scanSummary = nil
                scanErrorMessage = error.localizedDescription
            }
        } else {
            scanSummary = nil
            scanErrorMessage = nil
        }

        return ImportedComicsImportResult(
            importedDestinationName: destinationResolution.descriptor.name,
            createdLibrary: destinationResolution.wasCreated,
            importedComicCount: importedComicCount,
            scanSummary: scanSummary,
            scanErrorMessage: scanErrorMessage,
            unsupportedItemNames: unsupportedItemNames.sorted(),
            failedItemNames: failedItemNames.sorted()
        )
    }

    func availableDestinationOptions() throws -> [LibraryImportDestinationOption] {
        let descriptors = try store.load()
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
                subtitle: "Managed import library. It will be created automatically if needed.",
                detail: nil,
                availability: .available
            )
        ]

        options.append(
            contentsOf: sortedDescriptors
                .filter { $0.sourcePath != importedComicsRootPath }
                .map { descriptor in
                let accessSnapshot = storageManager.accessSnapshot(
                    for: descriptor,
                    inspector: SQLiteDatabaseInspector()
                )
                let availability = importAvailability(
                    for: descriptor,
                    accessSnapshot: accessSnapshot
                )
                return LibraryImportDestinationOption(
                    selection: .library(descriptor.id),
                    title: descriptor.name,
                    subtitle: importSubtitle(
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
        if descriptor.storageMode == .mirrored {
            throw ImportDestinationValidationError.destinationLibraryMirrored(descriptor.name)
        }

        let accessSnapshot = storageManager.accessSnapshot(
            for: descriptor,
            inspector: SQLiteDatabaseInspector()
        )
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

    private func ensureIndexedLibrary(for descriptor: LibraryDescriptor) throws -> LibraryScanSummary {
        let databaseURL = storageManager.databaseURL(for: descriptor)
        let accessSession = try storageManager.makeAccessSession(for: descriptor)
        return try withExtendedLifetime(accessSession) {
            try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
            return try libraryScanner.rescanLibrary(
                sourceRootURL: accessSession.sourceURL,
                databaseURL: databaseURL
            )
        }
    }

    private func importAvailability(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot
    ) -> LibraryImportDestinationOption.Availability {
        if descriptor.storageMode == .mirrored {
            return .unavailable("Mirrored desktop library. Keep using it for browsing, not direct imports.")
        }

        if !accessSnapshot.sourceWritable {
            return .unavailable("Currently read-only on this device.")
        }

        return .available
    }

    private func importSubtitle(
        for descriptor: LibraryDescriptor,
        accessSnapshot: LibraryAccessSnapshot,
        availability: LibraryImportDestinationOption.Availability
    ) -> String {
        switch availability {
        case .available:
            return "Copy imported comics into this library and refresh it automatically."
        case .unavailable:
            if descriptor.storageMode == .mirrored {
                return "Compatible for reading and metadata mirroring, but not as a direct import target."
            }

            if !accessSnapshot.sourceWritable {
                return "This library is readable, but its source folder is currently read-only."
            }

            return "This library cannot receive imports right now."
        }
    }

    private func importResource(
        at sourceURL: URL,
        into destinationDirectoryURL: URL,
        traverseDirectories: Bool,
        accessSecurityScopedResources: Bool,
        importedComicCount: inout Int,
        unsupportedItemNames: inout [String],
        failedItemNames: inout [String]
    ) throws {
        let scopedAccess = accessSecurityScopedResources
            ? sourceURL.startAccessingSecurityScopedResource()
            : false
        defer {
            if scopedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

        if values.isDirectory == true {
            guard traverseDirectories else {
                unsupportedItemNames.append(sourceURL.lastPathComponent)
                return
            }

            try importDirectoryContents(
                at: sourceURL,
                into: destinationDirectoryURL,
                importedComicCount: &importedComicCount,
                unsupportedItemNames: &unsupportedItemNames,
                failedItemNames: &failedItemNames
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
            try fileManager.copyItem(
                at: sourceURL,
                to: uniqueDestinationURL(for: sourceURL, in: destinationDirectoryURL)
            )
            importedComicCount += 1
        } catch {
            failedItemNames.append(sourceURL.lastPathComponent)
        }
    }

    private func importDirectoryContents(
        at directoryURL: URL,
        into destinationDirectoryURL: URL,
        importedComicCount: inout Int,
        unsupportedItemNames: inout [String],
        failedItemNames: inout [String]
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
            let values = try? candidateURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                continue
            }

            guard values?.isRegularFile == true, supportsComicFile(at: candidateURL) else {
                continue
            }

            discoveredAnyComic = true

            do {
                try fileManager.copyItem(
                    at: candidateURL,
                    to: uniqueDestinationURL(for: candidateURL, in: destinationDirectoryURL)
                )
                importedComicCount += 1
            } catch {
                failedItemNames.append(candidateURL.lastPathComponent)
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

    private func supportsComicFile(at url: URL) -> Bool {
        supportedComicFileExtensions.contains(url.pathExtension.lowercased())
    }
}
