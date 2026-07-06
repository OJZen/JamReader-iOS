import XCTest
@testable import JamReader

final class RemoteComicReadingSessionTests: XCTestCase {
    private let serverID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let modifiedAt = Date(timeIntervalSince1970: 1_000)
    private let openedAt = Date(timeIntervalSince1970: 2_000)

    func testProgressTextAndPageIndexUseReaderFriendlyDefaults() {
        XCTAssertEqual(makeSession(read: true).progressText, "Read")
        XCTAssertEqual(makeSession(pageCount: 42, currentPage: 8, hasBeenOpened: true).progressText, "Page 8 / 42")
        XCTAssertEqual(makeSession(pageCount: nil, currentPage: 8, hasBeenOpened: true).progressText, "Page 8")
        XCTAssertEqual(makeSession(pageCount: 42, currentPage: 0, hasBeenOpened: false).progressText, "42 pages")
        XCTAssertEqual(makeSession(pageCount: nil, currentPage: 0, hasBeenOpened: false).progressText, "Unread")
        XCTAssertEqual(makeSession(currentPage: -2).pageIndex, 0)
        XCTAssertEqual(makeSession(currentPage: 3).pageIndex, 2)
    }

    func testBookmarkPageIndicesNormalizeOnInitAndDecode() throws {
        let session = makeSession(bookmarkPageIndices: [4, 1, 4, -2, 0])

        XCTAssertEqual(session.bookmarkPageIndices, [0, 1, 4])

        let encodedData = try JSONEncoder().encode(session)
        let decodedSession = try JSONDecoder().decode(RemoteComicReadingSession.self, from: encodedData)

        XCTAssertEqual(decodedSession.bookmarkPageIndices, [0, 1, 4])
    }

    func testDirectoryItemAndComicReferencePreserveRemoteIdentity() {
        let session = makeSession(
            providerKind: .webdav,
            shareName: "/dav",
            cacheScopeKey: "webdav|https://nas.local/dav",
            path: "/Series/Volume",
            fileName: "Volume",
            contentKind: .imageDirectory,
            pageCount: 12
        )

        let item = session.directoryItem
        XCTAssertEqual(item.id, "55555555-5555-5555-5555-555555555555|webdav|/dav|webdav|https://nas.local/dav|/Series/Volume")
        XCTAssertEqual(item.kind, .comicDirectory)
        XCTAssertEqual(item.pageCountHint, 12)
        XCTAssertEqual(item.cacheScopeKey, "webdav|https://nas.local/dav")

        let reference = session.comicFileReference
        XCTAssertEqual(reference.serverID, session.serverID)
        XCTAssertEqual(reference.providerKind, .webdav)
        XCTAssertEqual(reference.shareName, "/dav")
        XCTAssertEqual(reference.cacheScopeKey, "webdav|https://nas.local/dav")
        XCTAssertEqual(reference.path, "/Series/Volume")
        XCTAssertEqual(reference.contentKind, .imageDirectory)
        XCTAssertEqual(reference.pageCountHint, 12)
    }

    func testResolvedComicFileReferenceFillsLegacySessionCacheScopeFromMatchingProfile() {
        let profile = RemoteServerProfile(
            id: serverID,
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: "Comics",
            createdAt: openedAt,
            updatedAt: openedAt
        )
        let legacySession = makeSession(cacheScopeKey: nil)

        let resolvedReference = legacySession.resolvedComicFileReference(for: profile)

        XCTAssertEqual(resolvedReference.cacheScopeKey, "smb|nas.local|445|Comics")
        XCTAssertTrue(legacySession.matches(profile: profile))
        XCTAssertTrue(legacySession.matches(reference: resolvedReference))
    }

    func testScopedSessionRejectsMismatchedProfileAndReferenceScope() {
        let session = makeSession(cacheScopeKey: "smb|nas.local|445|Comics")
        let mismatchedProfile = RemoteServerProfile(
            id: serverID,
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: "Other",
            createdAt: openedAt,
            updatedAt: openedAt
        )
        let mismatchedReference = makeReference(cacheScopeKey: "smb|nas.local|445|Other")

        XCTAssertFalse(session.matches(profile: mismatchedProfile))
        XCTAssertFalse(session.matches(reference: mismatchedReference))
        XCTAssertTrue(session.matches(reference: makeReference(cacheScopeKey: nil)))
    }

    private func makeSession(
        providerKind: RemoteProviderKind = .smb,
        shareName: String = "Comics",
        cacheScopeKey: String? = "smb|nas.local|445|Comics",
        path: String = "/Series/book.cbz",
        fileName: String = "book.cbz",
        contentKind: RemoteComicReferenceKind = .file,
        pageCount: Int? = 24,
        currentPage: Int = 1,
        hasBeenOpened: Bool = true,
        read: Bool = false,
        bookmarkPageIndices: [Int] = []
    ) -> RemoteComicReadingSession {
        RemoteComicReadingSession(
            serverID: serverID,
            providerKind: providerKind,
            serverName: "NAS",
            shareName: shareName,
            cacheScopeKey: cacheScopeKey,
            path: path,
            fileName: fileName,
            contentKind: contentKind,
            pageCount: pageCount,
            currentPage: currentPage,
            hasBeenOpened: hasBeenOpened,
            read: read,
            lastTimeOpened: openedAt,
            fileSize: 1024,
            modifiedAt: modifiedAt,
            bookmarkPageIndices: bookmarkPageIndices
        )
    }

    private func makeReference(cacheScopeKey: String?) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID,
            providerKind: .smb,
            shareName: "Comics",
            cacheScopeKey: cacheScopeKey,
            path: "/Series/book.cbz",
            fileName: "book.cbz",
            fileSize: 1024,
            modifiedAt: modifiedAt,
            contentKind: .file,
            pageCountHint: 24,
            coverPath: nil
        )
    }
}
