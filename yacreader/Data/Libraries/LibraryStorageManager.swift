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

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func registerLibrary(at sourceURL: URL, suggestedName: String? = nil) throws -> LibraryDescriptor {
        let standardizedURL = sourceURL.standardizedFileURL
        let isManagedLocalLibrary = isManagedLocalLibraryURL(standardizedURL)
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
        if isManagedLocalLibrary {
            bookmarkData = Data()
        } else {
            do {
                bookmarkData = try persistentBookmarkData(for: standardizedURL)
            } catch {
                throw LibraryStorageError.bookmarkCreationFailed
            }
        }

        let name = normalizedLibraryName(suggestedName, fallback: values.name ?? standardizedURL.lastPathComponent)
        let storageMode: LibraryStorageMode = fileManager.isWritableFile(atPath: standardizedURL.path) ? .inPlace : .mirrored

        let descriptor = LibraryDescriptor(
            id: UUID(),
            name: name,
            sourcePath: standardizedURL.path,
            sourceBookmarkData: bookmarkData,
            storageMode: storageMode,
            createdAt: Date(),
            updatedAt: Date()
        )

        try prepareMetadataDirectories(for: descriptor)

        return descriptor
    }

    func normalizeDescriptors(_ descriptors: [LibraryDescriptor]) -> [LibraryDescriptor] {
        descriptors.map { descriptor in
            (try? normalizedDescriptor(for: descriptor)) ?? descriptor
        }
    }

    func restoreSourceURL(for descriptor: LibraryDescriptor) throws -> URL {
        if descriptor.sourceBookmarkData.isEmpty || isManagedLocalLibraryPath(descriptor.sourcePath) {
            let sourceURL = try resolvedManagedLocalSourceURL(for: descriptor)
            if !fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
            }
            return sourceURL
        }

        var isStale = false

        do {
            return try resolveURL(
                fromBookmarkData: descriptor.sourceBookmarkData,
                isStale: &isStale
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
        switch descriptor.storageMode {
        case .inPlace:
            return URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
                .appendingPathComponent(".yacreaderlibrary", isDirectory: true)
        case .mirrored:
            return mirroredLibraryRootURL(for: descriptor)
        }
    }

    func databaseURL(for descriptor: LibraryDescriptor) -> URL {
        metadataRootURL(for: descriptor).appendingPathComponent("library.ydb")
    }

    func coversURL(for descriptor: LibraryDescriptor) -> URL {
        metadataRootURL(for: descriptor).appendingPathComponent("covers", isDirectory: true)
    }

    func ensureImportedComicsLibraryRootURL() throws -> URL {
        let importedRootURL = try importedComicsLibraryRootURL(createIfNeeded: true)

        if !fileManager.fileExists(atPath: importedRootURL.path) {
            try fileManager.createDirectory(
                at: importedRootURL,
                withIntermediateDirectories: true
            )
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
                let metadataURL = metadataRootURL(for: descriptor, sourceURL: sourceURL)
                return LibraryAccessSnapshot(
                    sourceExists: fileManager.fileExists(atPath: sourceURL.path),
                    sourceReadable: fileManager.isReadableFile(atPath: sourceURL.path),
                    sourceWritable: fileManager.isWritableFile(atPath: sourceURL.path),
                    metadataExists: fileManager.fileExists(atPath: metadataURL.path),
                    database: inspector.inspectDatabase(
                        at: metadataURL.appendingPathComponent("library.ydb")
                    )
                )
            }
        } catch {
            return LibraryAccessSnapshot(lastError: error.localizedDescription)
        }
    }

    func ensureLibraryMetadataStructure(for descriptor: LibraryDescriptor) throws {
        try prepareMetadataDirectories(for: descriptor)
    }

    private func prepareMetadataDirectories(for descriptor: LibraryDescriptor) throws {
        let metadataRootURL = metadataRootURL(for: descriptor)
        if !fileManager.fileExists(atPath: metadataRootURL.path) {
            try fileManager.createDirectory(at: metadataRootURL, withIntermediateDirectories: true)
        }

        let coversURL = coversURL(for: descriptor)
        if !fileManager.fileExists(atPath: coversURL.path) {
            try fileManager.createDirectory(at: coversURL, withIntermediateDirectories: true)
        }

        let identifierURL = metadataRootURL.appendingPathComponent("id")
        if !fileManager.fileExists(atPath: identifierURL.path) {
            try descriptor.id.uuidString.write(to: identifierURL, atomically: true, encoding: .utf8)
        }
    }

    private func mirroredLibraryRootURL(for descriptor: LibraryDescriptor) -> URL {
        let supportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let rootURL = (supportURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("Libraries", isDirectory: true)
            .appendingPathComponent(descriptor.id.uuidString, isDirectory: true)

        return rootURL
    }

    private func normalizedLibraryName(_ rawName: String?, fallback: String) -> String {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        let fallbackTrimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTrimmed.isEmpty ? "Untitled Library" : fallbackTrimmed
    }

    private func managedLibrariesRootURL() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("YACReader", isDirectory: true)
        .standardizedFileURL
    }

    private func importedComicsLibraryRootURL(createIfNeeded: Bool) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        .appendingPathComponent("YACReader", isDirectory: true)
        .appendingPathComponent("ImportedComics", isDirectory: true)
        .standardizedFileURL
    }

    private func isManagedLocalLibraryURL(_ url: URL) -> Bool {
        guard let managedRootURL = try? managedLibrariesRootURL() else {
            return false
        }

        return url.standardizedFileURL.path.hasPrefix(managedRootURL.path + "/")
            || url.standardizedFileURL.path == managedRootURL.path
    }

    private func isManagedLocalLibraryPath(_ path: String) -> Bool {
        isManagedLocalLibraryURL(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func resolvedManagedLocalSourceURL(for descriptor: LibraryDescriptor) throws -> URL {
        let managedRootURL = try managedLibrariesRootURL()

        if let relativePath = managedRelativePath(from: descriptor.sourcePath), !relativePath.isEmpty {
            return managedRootURL
                .appendingPathComponent(relativePath, isDirectory: true)
                .standardizedFileURL
        }

        let lastComponent = URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
            .standardizedFileURL
            .lastPathComponent

        if lastComponent == "ImportedComics" {
            return try ensureImportedComicsLibraryRootURL()
        }

        if !lastComponent.isEmpty, lastComponent != "/" {
            return managedRootURL
                .appendingPathComponent(lastComponent, isDirectory: true)
                .standardizedFileURL
        }

        return managedRootURL
    }

    private func managedRelativePath(from path: String) -> String? {
        let normalizedComponents = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .pathComponents

        guard let markerIndex = normalizedComponents.lastIndex(of: "YACReader"),
              markerIndex < normalizedComponents.endIndex - 1
        else {
            return nil
        }

        let relativeComponents = Array(normalizedComponents[(markerIndex + 1)...])
        return NSString.path(withComponents: relativeComponents)
    }

    private func normalizedDescriptor(for descriptor: LibraryDescriptor) throws -> LibraryDescriptor {
        let resolvedSourceURL = try restoreSourceURL(for: descriptor)
        var normalizedDescriptor = descriptor
        var didChange = false

        if normalizedDescriptor.sourcePath != resolvedSourceURL.path {
            normalizedDescriptor.sourcePath = resolvedSourceURL.path
            didChange = true
        }

        if isManagedLocalLibraryURL(resolvedSourceURL) {
            if !normalizedDescriptor.sourceBookmarkData.isEmpty {
                normalizedDescriptor.sourceBookmarkData = Data()
                didChange = true
            }
        } else {
            let scopedAccess = resolvedSourceURL.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess {
                    resolvedSourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let refreshedBookmarkData = try persistentBookmarkData(for: resolvedSourceURL)
            if normalizedDescriptor.sourceBookmarkData != refreshedBookmarkData {
                normalizedDescriptor.sourceBookmarkData = refreshedBookmarkData
                didChange = true
            }
        }

        if didChange {
            normalizedDescriptor.updatedAt = Date()
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

    private func resolveURL(
        fromBookmarkData bookmarkData: Data,
        isStale: inout Bool
    ) throws -> URL {
        try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func metadataRootURL(for descriptor: LibraryDescriptor, sourceURL: URL) -> URL {
        switch descriptor.storageMode {
        case .inPlace:
            return sourceURL.appendingPathComponent(".yacreaderlibrary", isDirectory: true)
        case .mirrored:
            return mirroredLibraryRootURL(for: descriptor)
        }
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
