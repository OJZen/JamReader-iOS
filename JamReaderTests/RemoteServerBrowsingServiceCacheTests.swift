import XCTest
@testable import JamReader

final class RemoteServerBrowsingServiceCacheTests: XCTestCase {
    private var harnesses: [RemoteCacheServiceTestHarness] = []

    override func tearDown() {
        for harness in harnesses {
            harness.remove()
        }
        harnesses.removeAll()
        super.tearDown()
    }

    func testCacheSummaryAggregatesScopedAndLegacyComicCachesForProfile() throws {
        let harness = try makeHarness()
        let profile = harness.makeSMBProfile()
        let scopedReference = harness.makeReference(
            for: profile,
            path: "/Series/Book.cbz",
            fileName: "Book.cbz",
            bytes: [1, 2, 3, 4],
            cacheScopeKey: profile.remoteCacheScopeKey
        )
        let legacyReference = harness.makeReference(
            for: profile,
            path: "/Legacy/Old.cbz",
            fileName: "Old.cbz",
            bytes: [5, 6, 7],
            cacheScopeKey: nil
        )

        try harness.writeCachedComic(for: scopedReference, bytes: [1, 2, 3, 4])
        try harness.writeCachedComic(for: legacyReference, bytes: [5, 6, 7])
        try harness.writeAuxiliaryFile(
            "leftover.tmp",
            bytes: [9, 9, 9],
            under: harness.resolver.cacheRootURL(for: profile)
        )

        let summary = harness.service.cacheSummary(for: profile)

        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertGreaterThan(summary.cachedComicBytes, 0)
        XCTAssertGreaterThan(summary.otherCacheBytes, 0)
        XCTAssertTrue(summary.hasCachedComics)
        XCTAssertTrue(summary.hasOtherCacheData)
        XCTAssertEqual(harness.service.cachedAvailability(for: scopedReference).kind, .current)
        XCTAssertEqual(harness.service.cachedAvailability(for: legacyReference).kind, .current)
    }

    func testClearCachedComicRemovesScopedLegacyAndPartialArtifactsForReference() throws {
        let harness = try makeHarness()
        let profile = harness.makeSMBProfile()
        let reference = harness.makeReference(
            for: profile,
            path: "/Series/Book.cbz",
            fileName: "Book.cbz",
            bytes: [1, 2, 3, 4],
            cacheScopeKey: profile.remoteCacheScopeKey
        )
        let scopedURL = harness.resolver.cachedFileURL(for: reference)
        let legacyURL = harness.resolver.legacyCachedFileURL(for: reference)

        try harness.writeCachedComic(for: reference, bytes: [1, 2, 3, 4], at: scopedURL)
        try harness.writeCachedComic(for: reference, bytes: [1, 2, 3, 4], at: legacyURL)
        try harness.writePartialArtifacts(for: scopedURL)
        try harness.writePartialArtifacts(for: legacyURL)

        try harness.service.clearCachedComic(for: reference)

        XCTAssertFalse(harness.fileManager.fileExists(atPath: scopedURL.path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: scopedURL.appendingPathExtension("yacmeta").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: scopedURL.appendingPathExtension("download").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: scopedURL.appendingPathExtension("download").appendingPathExtension("yacpartial").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: legacyURL.appendingPathExtension("yacmeta").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: legacyURL.appendingPathExtension("download").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: legacyURL.appendingPathExtension("download").appendingPathExtension("yacpartial").path))
        XCTAssertEqual(harness.service.cachedAvailability(for: reference).kind, .unavailable)
    }

    func testClearCachedComicsForProfileDoesNotRemoveOtherServerCaches() throws {
        let harness = try makeHarness()
        let firstProfile = harness.makeSMBProfile()
        let secondProfile = harness.makeSMBProfile(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Second NAS",
            host: "second.local"
        )
        let firstReference = harness.makeReference(
            for: firstProfile,
            path: "/Series/First.cbz",
            fileName: "First.cbz",
            bytes: [1, 2, 3],
            cacheScopeKey: firstProfile.remoteCacheScopeKey
        )
        let firstLegacyReference = harness.makeReference(
            for: firstProfile,
            path: "/Legacy/First.cbz",
            fileName: "First.cbz",
            bytes: [4, 5, 6],
            cacheScopeKey: nil
        )
        let secondReference = harness.makeReference(
            for: secondProfile,
            path: "/Series/Second.cbz",
            fileName: "Second.cbz",
            bytes: [7, 8, 9],
            cacheScopeKey: secondProfile.remoteCacheScopeKey
        )

        try harness.writeCachedComic(for: firstReference, bytes: [1, 2, 3])
        try harness.writeCachedComic(for: firstLegacyReference, bytes: [4, 5, 6])
        try harness.writeCachedComic(for: secondReference, bytes: [7, 8, 9])
        let firstReferenceURL = harness.resolver.cachedFileURL(for: firstReference)
        try harness.fileManager.removeItem(
            at: firstReferenceURL.appendingPathExtension("yacmeta")
        )
        let firstAuxiliaryURL = try harness.writeAuxiliaryFile(
            "unfinished.partial",
            bytes: [8, 8, 8],
            under: harness.resolver.cacheRootURL(for: firstProfile)
        )
        let nestedPartialComicURL = try harness.writeAuxiliaryFile(
            "Series/Interrupted.download/bonus.cbz",
            bytes: [6, 6, 6],
            under: harness.resolver.cacheRootURL(for: firstProfile)
        )

        XCTAssertEqual(harness.service.cacheSummary(for: firstProfile).fileCount, 2)
        try harness.service.clearCachedComics(for: firstProfile)

        XCTAssertEqual(harness.service.cacheSummary(for: firstProfile).fileCount, 0)
        XCTAssertTrue(harness.service.cacheSummary(for: firstProfile).hasOtherCacheData)
        XCTAssertEqual(harness.service.cacheSummary(for: secondProfile).fileCount, 1)
        XCTAssertTrue(harness.fileManager.fileExists(atPath: firstAuxiliaryURL.path))
        XCTAssertTrue(harness.fileManager.fileExists(atPath: nestedPartialComicURL.path))
        XCTAssertEqual(harness.service.cachedAvailability(for: firstReference).kind, .unavailable)
        XCTAssertEqual(harness.service.cachedAvailability(for: firstLegacyReference).kind, .unavailable)
        XCTAssertEqual(harness.service.cachedAvailability(for: secondReference).kind, .current)
    }

    func testClearOtherCachedDataKeepsDownloadedComics() throws {
        let harness = try makeHarness()
        let profile = harness.makeWebDAVProfile()
        let reference = harness.makeReference(
            for: profile,
            path: "/Series/Web.cbz",
            fileName: "Web.cbz",
            bytes: [1, 2, 3, 4, 5],
            cacheScopeKey: profile.remoteCacheScopeKey
        )
        let cachedURL = harness.resolver.cachedFileURL(for: reference)
        let auxiliaryURL = try harness.writeAuxiliaryFile(
            "orphan.partial",
            bytes: [8, 8, 8],
            under: harness.resolver.cacheRootURL(for: profile)
        )

        try harness.writeCachedComic(for: reference, bytes: [1, 2, 3, 4, 5], at: cachedURL)

        XCTAssertTrue(harness.service.cacheSummary(for: profile).hasOtherCacheData)

        try harness.service.clearOtherCachedData(for: profile)

        XCTAssertTrue(harness.fileManager.fileExists(atPath: cachedURL.path))
        XCTAssertTrue(harness.fileManager.fileExists(atPath: cachedURL.appendingPathExtension("yacmeta").path))
        XCTAssertFalse(harness.fileManager.fileExists(atPath: auxiliaryURL.path))
        XCTAssertEqual(harness.service.cachedAvailability(for: reference).kind, .current)
        XCTAssertEqual(harness.service.cacheSummary(for: profile).fileCount, 1)
        XCTAssertFalse(harness.service.cacheSummary(for: profile).hasOtherCacheData)
    }

    func testActiveReaderLeaseProtectsCachedComicFromRemoval() throws {
        let harness = try makeHarness()
        let profile = harness.makeSMBProfile()
        let reference = harness.makeReference(
            for: profile,
            path: "/Series/Book.cbz",
            fileName: "Book.cbz",
            bytes: [1, 2, 3, 4],
            cacheScopeKey: profile.remoteCacheScopeKey
        )
        let cachedURL = harness.resolver.cachedFileURL(for: reference)

        try harness.writeCachedComic(for: reference, bytes: [1, 2, 3, 4], at: cachedURL)

        let leaseToken = harness.service.registerActiveReaderLease(for: reference)
        try harness.service.clearCachedComic(for: reference)

        XCTAssertTrue(harness.fileManager.fileExists(atPath: cachedURL.path))
        XCTAssertThrowsError(try harness.service.clearCachedComics(for: profile))

        harness.service.unregisterActiveReaderLease(leaseToken, for: reference)
        try harness.service.clearCachedComic(for: reference)

        XCTAssertFalse(harness.fileManager.fileExists(atPath: cachedURL.path))
    }

    private func makeHarness(testName: String = #function) throws -> RemoteCacheServiceTestHarness {
        let harness = try RemoteCacheServiceTestHarness.make(testName: testName)
        harnesses.append(harness)
        return harness
    }
}

private final class TestCachesFileManager: FileManager {
    private let cachesRootURL: URL

    init(cachesRootURL: URL) {
        self.cachesRootURL = cachesRootURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .cachesDirectory && domainMask == .userDomainMask {
            return [cachesRootURL]
        }

        return super.urls(for: directory, in: domainMask)
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .cachesDirectory && domain == .userDomainMask {
            if shouldCreate && !fileExists(atPath: cachesRootURL.path) {
                try createDirectory(at: cachesRootURL, withIntermediateDirectories: true)
            }
            return cachesRootURL
        }

        return try super.url(
            for: directory,
            in: domain,
            appropriateFor: url,
            create: shouldCreate
        )
    }
}

private struct RemoteCacheServiceTestHarness {
    let rootURL: URL
    let cachesURL: URL
    let remoteComicCacheRootURL: URL
    let fileManager: TestCachesFileManager
    let resolver: RemoteCachePathResolver
    let service: RemoteServerBrowsingService

    static func make(testName: String = #function) throws -> RemoteCacheServiceTestHarness {
        let sanitizedTestName = testName
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: " ", with: "-")
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JamReaderTests", isDirectory: true)
            .appendingPathComponent(sanitizedTestName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cachesURL = rootURL.appendingPathComponent("Caches", isDirectory: true)
        let remoteComicCacheRootURL = cachesURL
            .appendingPathComponent("JamReader", isDirectory: true)
            .appendingPathComponent("RemoteComics", isDirectory: true)
        let fileManager = TestCachesFileManager(cachesRootURL: cachesURL)
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: remoteComicCacheRootURL)

        try fileManager.createDirectory(at: cachesURL, withIntermediateDirectories: true)

        return RemoteCacheServiceTestHarness(
            rootURL: rootURL,
            cachesURL: cachesURL,
            remoteComicCacheRootURL: remoteComicCacheRootURL,
            fileManager: fileManager,
            resolver: resolver,
            service: RemoteServerBrowsingService(fileManager: fileManager)
        )
    }

    func remove() {
        try? fileManager.removeItem(at: rootURL)
    }

    func makeSMBProfile(
        id: UUID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        name: String = "NAS",
        host: String = "nas.local"
    ) -> RemoteServerProfile {
        RemoteServerProfile(
            id: id,
            name: name,
            providerKind: .smb,
            host: host,
            port: 445,
            shareName: "Comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    func makeWebDAVProfile() -> RemoteServerProfile {
        RemoteServerProfile(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "WebDAV",
            providerKind: .webdav,
            host: "https://dav.example.com",
            port: 443,
            shareName: "/dav/comics",
            authenticationMode: .guest,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    func makeReference(
        for profile: RemoteServerProfile,
        path: String,
        fileName: String,
        bytes: [UInt8],
        cacheScopeKey: String?
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: profile.id,
            providerKind: profile.providerKind,
            shareName: profile.normalizedProviderRootIdentifier,
            cacheScopeKey: cacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: Int64(bytes.count),
            modifiedAt: Date(timeIntervalSince1970: 200),
            contentKind: .file,
            pageCountHint: nil,
            coverPath: nil
        )
    }

    func writeCachedComic(
        for reference: RemoteComicFileReference,
        bytes: [UInt8],
        at explicitURL: URL? = nil
    ) throws {
        let fileURL = explicitURL ?? resolver.cachedFileURL(for: reference)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: fileURL)
        let metadata = TestCachedRemoteComicMetadata(
            cacheScopeKey: reference.cacheScopeKey,
            path: reference.path,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt,
            contentKind: reference.contentKind,
            cachedByteCount: nil
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: fileURL.appendingPathExtension("yacmeta"), options: .atomic)
    }

    func writePartialArtifacts(for cachedURL: URL) throws {
        let partialURL = cachedURL.appendingPathExtension("download")
        try fileManager.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([7, 7]).write(to: partialURL)
        let partialMetadata = TestCachedRemoteComicMetadata(
            cacheScopeKey: nil,
            path: nil,
            fileSize: nil,
            modifiedAt: nil,
            contentKind: .file,
            cachedByteCount: nil
        )
        try JSONEncoder()
            .encode(partialMetadata)
            .write(to: partialURL.appendingPathExtension("yacpartial"), options: .atomic)
    }

    @discardableResult
    func writeAuxiliaryFile(
        _ relativePath: String,
        bytes: [UInt8],
        under rootURL: URL
    ) throws -> URL {
        let fileURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: fileURL)
        return fileURL
    }
}

private struct TestCachedRemoteComicMetadata: Codable {
    let cacheScopeKey: String?
    let path: String?
    let fileSize: Int64?
    let modifiedAt: Date?
    let contentKind: RemoteComicReferenceKind
    let cachedByteCount: Int64?
}
