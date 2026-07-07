import Foundation
import os

enum LibraryStorageError: LocalizedError {
    case invalidFolder
    case bookmarkCreationFailed
    case bookmarkResolutionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            return "The selected URL is not a valid library folder."
        case .bookmarkCreationFailed:
            return "Unable to create a persistent bookmark for the selected folder."
        case .bookmarkResolutionFailed:
            return "Unable to restore access to the selected library folder."
        }
    }
}

struct LibraryStorageFootprintSummary: Hashable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = LibraryStorageFootprintSummary(fileCount: 0, totalBytes: 0)

    var isEmpty: Bool {
        fileCount == 0 || totalBytes <= 0
    }

    var summaryText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

final class LibraryStorageManager {
    private let importedComicsDirectoryName = "ImportedComics"
    private let managedLibrariesDirectoryName = "Libraries"
    private let fileManager: FileManager
    private let database: AppLibraryDatabase
    private let assetStore: LibraryAssetStore
    private let logger = AppLog.library
    private let fallbackLogLock = NSLock()
    private var loggedFallbackKeys: Set<String> = []

    init(
        fileManager: FileManager = .default,
        database: AppLibraryDatabase = AppLibraryDatabase()
    ) {
        self.fileManager = fileManager
        self.database = database
        self.assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
    }

    func registerLibrary(
        at sourceURL: URL,
        suggestedName: String? = nil,
        preferredID: UUID? = nil
    ) throws -> LibraryDescriptor {
        let standardizedURL = sourceURL.standardizedFileURL
        let isManagedURL = isManagedLocalLibraryURL(standardizedURL)
        let scoped = standardizedURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
        guard values.isDirectory == true else {
            throw LibraryStorageError.invalidFolder
        }

        let bookmarkData: Data
        if isManagedURL {
            bookmarkData = Data()
        } else {
            do {
                bookmarkData = try persistentBookmarkData(for: standardizedURL)
            } catch {
                throw LibraryStorageError.bookmarkCreationFailed
            }
        }

        let descriptor = LibraryDescriptor(
            id: preferredID ?? UUID(),
            kind: kind(for: standardizedURL),
            name: normalizedLibraryName(suggestedName, fallback: values.name ?? standardizedURL.lastPathComponent),
            rootPath: standardizedURL.path,
            bookmarkData: bookmarkData,
            createdAt: Date(),
            updatedAt: Date()
        )

        try ensureLibraryMetadataStructure(for: descriptor)
        return descriptor
    }

    func createManagedLibrary(named proposedName: String) throws -> LibraryDescriptor {
        let libraryID = UUID()
        let rootURL = try managedLibraryRootURL(
            for: libraryID,
            name: proposedName,
            createIfNeeded: true
        )
        var descriptor = try registerLibrary(
            at: rootURL,
            suggestedName: proposedName,
            preferredID: libraryID
        )
        descriptor.kind = .appManaged
        return descriptor
    }

    func normalizeDescriptors(_ descriptors: [LibraryDescriptor]) -> [LibraryDescriptor] {
        descriptors.map { descriptor in
            do {
                return try normalizedDescriptor(for: descriptor)
            } catch {
                logger.warning(
                    "Library descriptor normalize fallback libraryID=\(descriptor.id.uuidString, privacy: .public) kind=\(descriptor.kind.rawValue, privacy: .public) root=\(AppLogSanitizer.path(descriptor.rootPath), privacy: .public) result=unchanged error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
                return descriptor
            }
        }
    }

    func restoreSourceURL(for descriptor: LibraryDescriptor) throws -> URL {
        if shouldResolveImportedComicsRoot(for: descriptor) {
            return try importedComicsLibraryRootURL(createIfNeeded: true)
        }

        if shouldResolveManagedLibraryRoot(for: descriptor) {
            return try appManagedLibraryRootURL(for: descriptor, createIfNeeded: true)
        }

        if descriptor.bookmarkData.isEmpty || isManagedLocalLibraryPath(descriptor.rootPath) {
            let sourceURL = URL(fileURLWithPath: descriptor.rootPath, isDirectory: true).standardizedFileURL
            if !fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
            }
            return sourceURL
        }

        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: descriptor.bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
        } catch {
            throw LibraryStorageError.bookmarkResolutionFailed
        }
    }

    func makeAccessSession(for descriptor: LibraryDescriptor) throws -> LibraryAccessSession {
        let sourceURL = try restoreSourceURL(for: descriptor)
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        return LibraryAccessSession(sourceURL: sourceURL, isSecurityScoped: isSecurityScoped)
    }

    func withScopedSourceAccess<T>(
        for descriptor: LibraryDescriptor,
        _ body: (LibraryAccessSession) throws -> T
    ) throws -> T {
        let session = try makeAccessSession(for: descriptor)
        return try body(session)
    }

    func metadataRootURL(for descriptor: LibraryDescriptor) -> URL {
        do {
            return try assetStore.rootURL(for: descriptor.id)
        } catch {
            let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(descriptor.id.uuidString, isDirectory: true)
            logStorageFallbackOnce(
                reason: "metadataRootURL",
                descriptor: descriptor,
                fallbackURL: fallbackURL,
                error: error
            )
            return fallbackURL
        }
    }

    func databaseURL(for descriptor: LibraryDescriptor) -> URL {
        do {
            return try database.contextualDatabaseURL(for: descriptor.id)
        } catch {
            let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: false)
            logStorageFallbackOnce(
                reason: "databaseURL",
                descriptor: descriptor,
                fallbackURL: fallbackURL,
                error: error
            )
            return fallbackURL
        }
    }

    func coversURL(for descriptor: LibraryDescriptor) -> URL {
        do {
            return try assetStore.coversRootURL(for: descriptor.id)
        } catch {
            let fallbackURL = metadataRootURL(for: descriptor).appendingPathComponent("covers", isDirectory: true)
            logStorageFallbackOnce(
                reason: "coversURL",
                descriptor: descriptor,
                fallbackURL: fallbackURL,
                error: error
            )
            return fallbackURL
        }
    }

    func ensureImportedComicsLibraryRootURL() throws -> URL {
        let importedRootURL = try importedComicsLibraryRootURL(createIfNeeded: true)
        if !fileManager.fileExists(atPath: importedRootURL.path) {
            try fileManager.createDirectory(at: importedRootURL, withIntermediateDirectories: true)
        }
        return importedRootURL
    }

    func importedComicsLibraryStorageSummary() -> LibraryStorageFootprintSummary {
        let importedRootURL: URL
        do {
            importedRootURL = try importedComicsLibraryRootURL(createIfNeeded: false)
        } catch {
            logStorageFallbackOnce(
                reason: "importedComicsStorageSummaryRoot",
                descriptor: nil,
                fallbackURL: nil,
                error: error
            )
            return .empty
        }

        guard fileManager.fileExists(atPath: importedRootURL.path) else {
            return .empty
        }

        return directoryFootprint(at: importedRootURL)
    }

    func accessSnapshot(for descriptor: LibraryDescriptor, inspector: SQLiteDatabaseInspector) -> LibraryAccessSnapshot {
        do {
            return try withScopedSourceAccess(for: descriptor) { session in
                let sourceURL = session.sourceURL.standardizedFileURL
                let metadataURL = metadataRootURL(for: descriptor)
                return LibraryAccessSnapshot(
                    sourceExists: fileManager.fileExists(atPath: sourceURL.path),
                    sourceReadable: fileManager.isReadableFile(atPath: sourceURL.path),
                    sourceWritable: fileManager.isWritableFile(atPath: sourceURL.path),
                    metadataExists: fileManager.fileExists(atPath: metadataURL.path),
                    database: inspector.inspectDatabase(at: databaseURL(for: descriptor))
                )
            }
        } catch {
            logger.warning(
                "Library access snapshot failed libraryID=\(descriptor.id.uuidString, privacy: .public) kind=\(descriptor.kind.rawValue, privacy: .public) root=\(AppLogSanitizer.path(descriptor.rootPath), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return LibraryAccessSnapshot(lastError: error.userFacingMessage)
        }
    }

    func ensureLibraryMetadataStructure(for descriptor: LibraryDescriptor) throws {
        try assetStore.ensureLibraryDirectories(for: descriptor.id)
    }

    func deleteManagedLibraryFilesIfNeeded(for descriptor: LibraryDescriptor) throws {
        switch descriptor.kind {
        case .linkedFolder:
            return
        case .importedComics:
            let rootURL = try importedComicsLibraryRootURL(createIfNeeded: false)
            guard fileManager.fileExists(atPath: rootURL.path) else {
                return
            }
            try fileManager.removeItem(at: rootURL)
        case .appManaged:
            let libraryRootURL = try appManagedLibraryRootURL(for: descriptor, createIfNeeded: false)
            let managedRootURL = try managedLibrariesRootURL(createIfNeeded: false)

            let managedRootPath = managedRootURL.path
            let libraryRootPath = libraryRootURL.path
            guard libraryRootPath.hasPrefix(managedRootPath + "/") else {
                logger.warning(
                    "Library managed files delete skipped libraryID=\(descriptor.id.uuidString, privacy: .public) reason=outsideManagedRoot root=\(AppLogSanitizer.path(libraryRootPath), privacy: .public)"
                )
                return
            }

            guard fileManager.fileExists(atPath: libraryRootPath) else {
                return
            }

            try fileManager.removeItem(at: libraryRootURL)
        }
    }

    private func normalizedLibraryName(_ rawName: String?, fallback: String) -> String {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallbackTrimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTrimmed.isEmpty ? "Untitled Library" : fallbackTrimmed
    }

    private func importedComicsLibraryRootURL(createIfNeeded: Bool) throws -> URL {
        let rootURL = try database
            .storageRootURL()
            .appendingPathComponent(importedComicsDirectoryName, isDirectory: true)
            .standardizedFileURL

        if createIfNeeded, !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private func managedLibrariesRootURL(createIfNeeded: Bool) throws -> URL {
        let rootURL = try database
            .storageRootURL()
            .appendingPathComponent(managedLibrariesDirectoryName, isDirectory: true)
            .standardizedFileURL

        if createIfNeeded, !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private func managedLibraryRootURL(
        for id: UUID,
        name: String,
        createIfNeeded: Bool
    ) throws -> URL {
        let baseURL = try managedLibrariesRootURL(createIfNeeded: createIfNeeded)
        let sanitizedName = sanitizedManagedLibraryDirectoryName(from: name)
        let folderName = "\(sanitizedName)-\(id.uuidString.prefix(8))"
        let rootURL = baseURL.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL

        if createIfNeeded, !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private func appManagedLibraryRootURL(
        for descriptor: LibraryDescriptor,
        createIfNeeded: Bool
    ) throws -> URL {
        let baseURL = try managedLibrariesRootURL(createIfNeeded: createIfNeeded)
        let existingFolderName = URL(fileURLWithPath: descriptor.rootPath, isDirectory: true)
            .standardizedFileURL
            .lastPathComponent

        let folderName: String
        if existingFolderName.isEmpty || existingFolderName == managedLibrariesDirectoryName {
            folderName = "\(sanitizedManagedLibraryDirectoryName(from: descriptor.name))-\(descriptor.id.uuidString.prefix(8))"
        } else {
            folderName = existingFolderName
        }

        let rootURL = baseURL.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
        if createIfNeeded, !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        return rootURL
    }

    private func isImportedComicsLibraryURL(_ url: URL) -> Bool {
        let importedURL: URL
        do {
            importedURL = try importedComicsLibraryRootURL(createIfNeeded: false)
        } catch {
            logStorageFallbackOnce(
                reason: "importedComicsKindCheckRoot",
                descriptor: nil,
                fallbackURL: nil,
                error: error
            )
            return false
        }

        return url.standardizedFileURL.path == importedURL.path
    }

    private func shouldResolveImportedComicsRoot(for descriptor: LibraryDescriptor) -> Bool {
        if descriptor.kind == .importedComics {
            return true
        }

        guard descriptor.bookmarkData.isEmpty else {
            return false
        }

        let candidateURL = URL(fileURLWithPath: descriptor.rootPath, isDirectory: true).standardizedFileURL
        return candidateURL.lastPathComponent == importedComicsDirectoryName
    }

    private func shouldResolveManagedLibraryRoot(for descriptor: LibraryDescriptor) -> Bool {
        if descriptor.kind == .appManaged {
            return true
        }

        guard descriptor.bookmarkData.isEmpty else {
            return false
        }

        let candidateURL = URL(fileURLWithPath: descriptor.rootPath, isDirectory: true).standardizedFileURL
        guard candidateURL.lastPathComponent != managedLibrariesDirectoryName else {
            return false
        }

        return candidateURL.path.contains("/\(managedLibrariesDirectoryName)/")
    }

    private func isManagedLocalLibraryURL(_ url: URL) -> Bool {
        let rootURL: URL
        do {
            rootURL = try database.storageRootURL()
        } catch {
            logStorageFallbackOnce(
                reason: "managedLibraryKindCheckRoot",
                descriptor: nil,
                fallbackURL: nil,
                error: error
            )
            return false
        }

        let standardizedPath = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return standardizedPath == rootPath || standardizedPath.hasPrefix(rootPath + "/")
    }

    private func isManagedLocalLibraryPath(_ path: String) -> Bool {
        isManagedLocalLibraryURL(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func normalizedDescriptor(for descriptor: LibraryDescriptor) throws -> LibraryDescriptor {
        let resolvedSourceURL = try restoreSourceURL(for: descriptor)
        var normalizedDescriptor = descriptor
        var didChange = false

        if normalizedDescriptor.rootPath != resolvedSourceURL.path {
            normalizedDescriptor.rootPath = resolvedSourceURL.path
            didChange = true
        }

        let normalizedKind = kind(for: resolvedSourceURL)
        if normalizedDescriptor.kind != normalizedKind {
            normalizedDescriptor.kind = normalizedKind
            didChange = true
        }

        if isManagedLocalLibraryURL(resolvedSourceURL) {
            if !normalizedDescriptor.bookmarkData.isEmpty {
                normalizedDescriptor.bookmarkData = Data()
                didChange = true
            }
        } else {
            let scoped = resolvedSourceURL.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    resolvedSourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let refreshedBookmarkData = try persistentBookmarkData(for: resolvedSourceURL)
            if normalizedDescriptor.bookmarkData != refreshedBookmarkData {
                normalizedDescriptor.bookmarkData = refreshedBookmarkData
                didChange = true
            }
        }

        if didChange {
            normalizedDescriptor.updatedAt = Date()
            try ensureLibraryMetadataStructure(for: normalizedDescriptor)
        }

        return normalizedDescriptor
    }

    private func kind(for url: URL) -> LibraryKind {
        if isImportedComicsLibraryURL(url) {
            return .importedComics
        }

        if isManagedLocalLibraryURL(url) {
            return .appManaged
        }

        return .linkedFolder
    }

    private func sanitizedManagedLibraryDirectoryName(from name: String) -> String {
        let fallback = "Library"
        let lowered = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let pieces = lowered.split { character in
            !(character.isLetter || character.isNumber)
        }
        let candidate = pieces.joined(separator: "-")
        if candidate.isEmpty {
            return fallback
        }

        return String(candidate.prefix(40))
    }

    private func persistentBookmarkData(for sourceURL: URL) throws -> Data {
        try sourceURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func logStorageFallbackOnce(
        reason: String,
        descriptor: LibraryDescriptor?,
        fallbackURL: URL?,
        error: Error
    ) {
        let descriptorKey = descriptor?.id.uuidString ?? "global"
        let key = "\(reason):\(descriptorKey)"
        guard shouldLogStorageFallback(key: key) else {
            return
        }

        let fallbackPath = fallbackURL.map { AppLogSanitizer.path($0.path) } ?? "none"
        let errorDescription = AppLogSanitizer.errorDescription(error)

        if let descriptor {
            logger.warning(
                "Library storage fallback reason=\(reason, privacy: .public) libraryID=\(descriptor.id.uuidString, privacy: .public) kind=\(descriptor.kind.rawValue, privacy: .public) root=\(AppLogSanitizer.path(descriptor.rootPath), privacy: .public) fallback=\(fallbackPath, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
        } else {
            logger.warning(
                "Library storage fallback reason=\(reason, privacy: .public) fallback=\(fallbackPath, privacy: .public) error=\(errorDescription, privacy: .public)"
            )
        }
    }

    private func shouldLogStorageFallback(key: String) -> Bool {
        fallbackLogLock.lock()
        defer {
            fallbackLogLock.unlock()
        }

        guard !loggedFallbackKeys.contains(key) else {
            return false
        }

        loggedFallbackKeys.insert(key)
        return true
    }

    private func directoryFootprint(at rootURL: URL) -> LibraryStorageFootprintSummary {
        let footprint = DiskUsageScanner.footprint(at: rootURL, fileManager: fileManager)
        return LibraryStorageFootprintSummary(
            fileCount: footprint.fileCount,
            totalBytes: footprint.totalBytes
        )
    }
}
