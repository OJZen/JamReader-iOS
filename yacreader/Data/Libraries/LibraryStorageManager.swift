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

final class LibraryStorageManager {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func registerLibrary(at sourceURL: URL, suggestedName: String? = nil) throws -> LibraryDescriptor {
        let standardizedURL = sourceURL.standardizedFileURL
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
        do {
            bookmarkData = try standardizedURL.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw LibraryStorageError.bookmarkCreationFailed
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

    func restoreSourceURL(for descriptor: LibraryDescriptor) throws -> URL {
        var isStale = false

        do {
            return try URL(
                resolvingBookmarkData: descriptor.sourceBookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
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
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let importedRootURL = supportURL
            .appendingPathComponent("YACReader", isDirectory: true)
            .appendingPathComponent("ImportedComics", isDirectory: true)

        if !fileManager.fileExists(atPath: importedRootURL.path) {
            try fileManager.createDirectory(
                at: importedRootURL,
                withIntermediateDirectories: true
            )
        }

        return importedRootURL
    }

    func accessSnapshot(for descriptor: LibraryDescriptor, inspector: SQLiteDatabaseInspector) -> LibraryAccessSnapshot {
        do {
            return try withScopedSourceAccess(for: descriptor) { _ in
                let metadataURL = metadataRootURL(for: descriptor)
                return LibraryAccessSnapshot(
                    sourceExists: fileManager.fileExists(atPath: descriptor.sourcePath),
                    sourceReadable: fileManager.isReadableFile(atPath: descriptor.sourcePath),
                    sourceWritable: fileManager.isWritableFile(atPath: descriptor.sourcePath),
                    metadataExists: fileManager.fileExists(atPath: metadataURL.path),
                    database: inspector.inspectDatabase(at: databaseURL(for: descriptor))
                )
            }
        } catch {
            return LibraryAccessSnapshot(lastError: error.localizedDescription)
        }
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
}
