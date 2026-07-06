import XCTest
@testable import JamReader

final class RemoteDirectoryItemTests: XCTestCase {
    private let serverID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testItemIdentityIncludesServerProviderScopeAndPath() {
        let first = makeItem(cacheScopeKey: "smb|nas|445|Comics", path: "/A/book.cbz")
        let second = makeItem(cacheScopeKey: "smb|nas|445|Other", path: "/A/book.cbz")
        let third = makeItem(cacheScopeKey: "smb|nas|445|Comics", path: "/B/book.cbz")

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, third.id)
    }

    func testItemIdentitySeparatesServersProvidersAndShares() {
        let first = makeItem()
        let samePathDifferentServer = makeItem(
            serverID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let samePathDifferentProvider = makeItem(
            providerKind: .webdav,
            shareName: "/dav",
            cacheScopeKey: "webdav|https://nas.local/dav"
        )
        let samePathDifferentShare = makeItem(
            shareName: "Other",
            cacheScopeKey: "smb|nas|445|Other"
        )

        XCTAssertNotEqual(first.id, samePathDifferentServer.id)
        XCTAssertNotEqual(first.id, samePathDifferentProvider.id)
        XCTAssertNotEqual(first.id, samePathDifferentShare.id)
    }

    func testComicFilePresentationFlags() {
        let item = makeItem(name: "Book.PDF", kind: .comicFile)

        XCTAssertTrue(item.canOpenAsComic)
        XCTAssertFalse(item.isDirectory)
        XCTAssertEqual(item.comicReferenceKind, .file)
        XCTAssertEqual(item.fileExtension, "pdf")
        XCTAssertTrue(item.isPDFDocument)
        XCTAssertEqual(item.titleSystemImageName, "book.closed.fill")
    }

    func testComicDirectoryIsOpenableButNotAPDFDocument() {
        let item = makeItem(name: "Scans.pdf", kind: .comicDirectory)

        XCTAssertTrue(item.canOpenAsComic)
        XCTAssertTrue(item.isComicDirectory)
        XCTAssertEqual(item.comicReferenceKind, .imageDirectory)
        XCTAssertFalse(item.isPDFDocument)
    }

    func testRemoteComicFileReferenceIdentityIncludesReferenceKind() {
        let fileReference = makeReference(contentKind: .file)
        let directoryReference = makeReference(contentKind: .imageDirectory)

        XCTAssertNotEqual(fileReference.id, directoryReference.id)
        XCTAssertFalse(fileReference.isImageDirectoryComic)
        XCTAssertTrue(directoryReference.isImageDirectoryComic)
    }

    func testRemoteComicFileReferenceIdentitySeparatesRemoteScopes() {
        let first = makeReference()
        let samePathDifferentServer = makeReference(
            serverID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        let samePathDifferentProvider = makeReference(
            providerKind: .webdav,
            shareName: "/dav",
            cacheScopeKey: "webdav|https://nas.local/dav"
        )
        let samePathDifferentCacheScope = makeReference(
            cacheScopeKey: "smb|nas|445|Other"
        )

        XCTAssertNotEqual(first.id, samePathDifferentServer.id)
        XCTAssertNotEqual(first.id, samePathDifferentProvider.id)
        XCTAssertNotEqual(first.id, samePathDifferentCacheScope.id)
    }

    func testMakeComicFileReferencePreservesRemoteIdentityAndContentKind() throws {
        let item = makeItem(
            serverID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            providerKind: .webdav,
            shareName: "/dav",
            cacheScopeKey: "webdav|https://nas.local/dav",
            path: "/Series/Volume",
            name: "Volume",
            kind: .comicDirectory
        )

        let reference = try RemoteServerBrowsingService().makeComicFileReference(from: item)

        XCTAssertEqual(reference.serverID, item.serverID)
        XCTAssertEqual(reference.providerKind, item.providerKind)
        XCTAssertEqual(reference.shareName, item.shareName)
        XCTAssertEqual(reference.cacheScopeKey, item.cacheScopeKey)
        XCTAssertEqual(reference.path, item.path)
        XCTAssertEqual(reference.fileName, item.name)
        XCTAssertEqual(reference.fileSize, item.fileSize)
        XCTAssertEqual(reference.modifiedAt, item.modifiedAt)
        XCTAssertEqual(reference.contentKind, .imageDirectory)
        XCTAssertEqual(reference.pageCountHint, item.pageCountHint)
        XCTAssertEqual(reference.coverPath, item.coverPath)
    }

    private func makeItem(
        serverID: UUID? = nil,
        providerKind: RemoteProviderKind = .smb,
        shareName: String = "Comics",
        cacheScopeKey: String = "smb|nas|445|Comics",
        path: String = "/A/book.cbz",
        name: String = "book.cbz",
        kind: RemoteDirectoryItemKind = .comicFile
    ) -> RemoteDirectoryItem {
        RemoteDirectoryItem(
            serverID: serverID ?? self.serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey,
            path: path,
            name: name,
            kind: kind,
            fileSize: 1024,
            modifiedAt: Date(timeIntervalSince1970: 100),
            pageCountHint: nil,
            coverPath: nil,
            previewItems: []
        )
    }

    private func makeReference(
        serverID: UUID? = nil,
        providerKind: RemoteProviderKind = .smb,
        shareName: String = "Comics",
        cacheScopeKey: String? = "smb|nas|445|Comics",
        path: String = "/A/book",
        fileName: String = "book.cbz",
        contentKind: RemoteComicReferenceKind = .file
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID ?? self.serverID,
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
