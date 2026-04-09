import Foundation

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
    private let fileManager: FileManager
    private let database: AppLibraryDatabase
    private let assetStore: LibraryAssetStore

    init(
        fileManager: FileManager = .default,
        database: AppLibraryDatabase = AppLibraryDatabase()
    ) {
        self.fileManager = fileManager
        self.database = database
        self.assetStore = LibraryAssetStore(database: database, fileManager: fileManager)
    }

    func registerLibrary(at sourceURL: URL, suggestedName: String? = nil) throws -> LibraryDescriptor {
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
            id: UUID(),
            kind: isImportedComicsLibraryURL(standardizedURL) ? .importedComics : .linkedFolder,
            name: normalizedLibraryName(suggestedName, fallback: values.name ?? standardizedURL.lastPathComponent),
            rootPath: standardizedURL.path,
            bookmarkData: bookmarkData,
            createdAt: Date(),
            updatedAt: Date()
        )

        try ensureLibraryMetadataStructure(for: descriptor)
        return descriptor
    }

    func normalizeDescriptors(_ descriptors: [LibraryDescriptor]) -> [LibraryDescriptor] {
        descriptors.map { descriptor in
            (try? normalizedDescriptor(for: descriptor)) ?? descriptor
        }
    }

    func restoreSourceURL(for descriptor: LibraryDescriptor) throws -> URL {
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
        (try? assetStore.rootURL(for: descriptor.id))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(descriptor.id.uuidString, isDirectory: true)
    }

    func databaseURL(for descriptor: LibraryDescriptor) -> URL {
        (try? database.contextualDatabaseURL(for: descriptor.id))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: false)
    }

    func coversURL(for descriptor: LibraryDescriptor) -> URL {
        (try? assetStore.coversRootURL(for: descriptor.id))
            ?? metadataRootURL(for: descriptor).appendingPathComponent("covers", isDirectory: true)
    }

    func ensureImportedComicsLibraryRootURL() throws -> URL {
        let importedRootURL = try importedComicsLibraryRootURL(createIfNeeded: true)
        if !fileManager.fileExists(atPath: importedRootURL.path) {
            try fileManager.createDirectory(at: importedRootURL, withIntermediateDirectories: true)
        }
        return importedRootURL
    }

    func importedComicsLibraryStorageSummary() -> LibraryStorageFootprintSummary {
        guard let importedRootURL = try? importedComicsLibraryRootURL(createIfNeeded: false),
              fileManager.fileExists(atPath: importedRootURL.path)
        else {
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
            return LibraryAccessSnapshot(lastError: error.userFacingMessage)
        }
    }

    func ensureLibraryMetadataStructure(for descriptor: LibraryDescriptor) throws {
        try assetStore.ensureLibraryDirectories(for: descriptor.id)
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
        try database
            .storageRootURL()
            .appendingPathComponent("ImportedComics", isDirectory: true)
            .standardizedFileURL
    }

    private func isImportedComicsLibraryURL(_ url: URL) -> Bool {
        guard let importedURL = try? importedComicsLibraryRootURL(createIfNeeded: false) else {
            return false
        }

        return url.standardizedFileURL.path == importedURL.path
    }

    private func isManagedLocalLibraryURL(_ url: URL) -> Bool {
        guard let rootURL = try? database.storageRootURL() else {
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

        let normalizedKind: LibraryKind = isImportedComicsLibraryURL(resolvedSourceURL) ? .importedComics : .linkedFolder
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

    private func persistentBookmarkData(for sourceURL: URL) throws -> Data {
        try sourceURL.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func directoryFootprint(at rootURL: URL) -> LibraryStorageFootprintSummary {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else {
            return .empty
        }

        var fileCount = 0
        var totalBytes: Int64 = 0

        while let itemURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys),
                  resourceValues.isRegularFile == true
            else {
                continue
            }

            fileCount += 1
            totalBytes += Int64(
                resourceValues.totalFileAllocatedSize
                    ?? resourceValues.fileAllocatedSize
                    ?? resourceValues.fileSize
                    ?? 0
            )
        }

        return LibraryStorageFootprintSummary(fileCount: fileCount, totalBytes: totalBytes)
    }
}
