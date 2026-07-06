import XCTest
@testable import JamReader

final class RemoteCachePathResolverTests: XCTestCase {
    private let serverID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    private let rootURL = URL(fileURLWithPath: "/tmp/jamreader-cache-root", isDirectory: true)

    func testScopedCachedFileURLUsesServerScopeAndSanitizedRemotePath() {
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: rootURL)
        let reference = makeReference(
            cacheScopeKey: "smb|nas.local|445|Comics",
            path: "/Series/../Book.cbz",
            fileName: "ignored.cbz"
        )

        let cachedURL = resolver.cachedFileURL(for: reference)

        XCTAssertEqual(
            cachedURL.path,
            "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/scope-5827a1588274bf80bba133f5/Series/Book.cbz"
        )
        XCTAssertFalse(cachedURL.pathComponents.contains(".."))
    }

    func testCachedFileURLFallsBackToFileNameWhenRemotePathIsEmpty() {
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: rootURL)
        let reference = makeReference(
            cacheScopeKey: "smb|nas.local|445|Comics",
            path: "",
            fileName: "book.cbz"
        )

        XCTAssertEqual(
            resolver.cachedFileURL(for: reference).path,
            "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/scope-5827a1588274bf80bba133f5/book.cbz"
        )
    }

    func testCandidateURLsIncludeScopedAndLegacyLocationsWithoutDuplicates() {
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: rootURL)
        let scopedReference = makeReference(
            cacheScopeKey: "smb|nas.local|445|Comics",
            path: "/Series/book.cbz"
        )
        let legacyReference = makeReference(
            cacheScopeKey: nil,
            path: "/Series/book.cbz"
        )

        XCTAssertEqual(
            resolver.cachedFileCandidateURLs(for: scopedReference).map(\.path),
            [
                "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/scope-5827a1588274bf80bba133f5/Series/book.cbz",
                "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/Comics/Series/book.cbz"
            ]
        )
        XCTAssertEqual(
            resolver.cachedFileCandidateURLs(for: legacyReference).map(\.path),
            [
                "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/Comics/Series/book.cbz"
            ]
        )
    }

    func testLegacyRootComponentsMatchProviderRules() {
        XCTAssertEqual(
            RemoteCachePathResolver.legacyCacheRootPathComponents(
                providerKind: .smb,
                providerRootIdentifier: "  Comics  "
            ),
            ["Comics"]
        )
        XCTAssertEqual(
            RemoteCachePathResolver.legacyCacheRootPathComponents(
                providerKind: .smb,
                providerRootIdentifier: " "
            ),
            ["share"]
        )
        XCTAssertEqual(
            RemoteCachePathResolver.legacyCacheRootPathComponents(
                providerKind: .webdav,
                providerRootIdentifier: "/dav//comics/"
            ),
            ["webdav", "dav", "comics"]
        )
        XCTAssertEqual(
            RemoteCachePathResolver.legacyCacheRootPathComponents(
                providerKind: .webdav,
                providerRootIdentifier: ""
            ),
            ["webdav-root"]
        )
    }

    func testProfileCacheRootsPreferScopedPathThenLegacyPath() {
        let resolver = RemoteCachePathResolver(remoteComicCacheRootURL: rootURL)
        let profile = RemoteServerProfile(
            id: serverID,
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: "Comics",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            resolver.cacheRootURLs(for: profile).map(\.path),
            [
                "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/scope-5827a1588274bf80bba133f5",
                "/tmp/jamreader-cache-root/66666666-6666-6666-6666-666666666666/Comics"
            ]
        )
        XCTAssertEqual(resolver.cacheRootURLs(for: nil).map(\.path), ["/tmp/jamreader-cache-root"])
    }

    private func makeReference(
        providerKind: RemoteProviderKind = .smb,
        shareName: String = "Comics",
        cacheScopeKey: String?,
        path: String,
        fileName: String = "book.cbz",
        contentKind: RemoteComicReferenceKind = .file
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: 1024,
            modifiedAt: Date(timeIntervalSince1970: 100),
            contentKind: contentKind,
            pageCountHint: nil,
            coverPath: nil
        )
    }
}
