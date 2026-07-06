import XCTest
@testable import JamReader

final class RemoteReadingProgressStorePersistenceTests: XCTestCase {
    private let serverID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testSaveProgressPersistsAndReloadsSessionsSortedByLastOpened() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profile = makeProfile(id: serverID, shareName: "Comics")
        let olderReference = makeReference(path: "/Series/older.cbz", fileName: "older.cbz")
        let newerReference = makeReference(path: "/Series/newer.cbz", fileName: "newer.cbz")

        try makeStore(directoryURL: directoryURL).saveProgress(
            makeProgress(currentPage: 3, lastTimeOpened: Date(timeIntervalSince1970: 100)),
            for: olderReference,
            profile: profile
        )
        try makeStore(directoryURL: directoryURL).saveProgress(
            makeProgress(currentPage: 8, lastTimeOpened: Date(timeIntervalSince1970: 200)),
            for: newerReference,
            profile: profile,
            bookmarkPageIndices: [7, 1, 7]
        )

        let reloadedStore = makeStore(directoryURL: directoryURL)
        let sessions = try reloadedStore.loadSessions()

        XCTAssertEqual(sessions.map(\.fileName), ["newer.cbz", "older.cbz"])
        XCTAssertEqual(sessions.first?.currentPage, 8)
        XCTAssertEqual(sessions.first?.bookmarkPageIndices, [1, 7])
        XCTAssertEqual(try reloadedStore.mostRecentSession()?.fileName, "newer.cbz")
        XCTAssertEqual(try reloadedStore.latestSessionsByServerID()[serverID]?.fileName, "newer.cbz")
    }

    func testSavingSameReferenceReplacesExistingSession() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profile = makeProfile(id: serverID, shareName: "Comics")
        let reference = makeReference(path: "/Series/book.cbz", fileName: "book.cbz")
        let store = makeStore(directoryURL: directoryURL)

        try store.saveProgress(
            makeProgress(currentPage: 2, lastTimeOpened: Date(timeIntervalSince1970: 100)),
            for: reference,
            profile: profile
        )
        try store.saveProgress(
            makeProgress(currentPage: 9, lastTimeOpened: Date(timeIntervalSince1970: 200)),
            for: reference,
            profile: profile
        )

        let sessions = try makeStore(directoryURL: directoryURL).loadSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.currentPage, 9)
    }

    func testMaximumStoredSessionsKeepsMostRecentSessions() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profile = makeProfile(id: serverID, shareName: "Comics")
        let store = makeStore(directoryURL: directoryURL, maximumStoredSessions: 2)

        for index in 1...3 {
            try store.saveProgress(
                makeProgress(
                    currentPage: index,
                    lastTimeOpened: Date(timeIntervalSince1970: TimeInterval(index))
                ),
                for: makeReference(path: "/Series/book-\(index).cbz", fileName: "book-\(index).cbz"),
                profile: profile
            )
        }

        XCTAssertEqual(
            try makeStore(directoryURL: directoryURL).loadSessions().map(\.fileName),
            ["book-3.cbz", "book-2.cbz"]
        )
    }

    func testDeleteSessionsForProfilePreservesOtherServers() throws {
        let directoryURL = try makeTemporaryDirectory()
        let firstProfile = makeProfile(id: serverID, shareName: "Comics")
        let secondServerID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let secondProfile = makeProfile(id: secondServerID, shareName: "Comics")
        let store = makeStore(directoryURL: directoryURL)

        try store.saveProgress(
            makeProgress(currentPage: 1, lastTimeOpened: Date(timeIntervalSince1970: 100)),
            for: makeReference(serverID: serverID, path: "/A/book.cbz", fileName: "book.cbz"),
            profile: firstProfile
        )
        try store.saveProgress(
            makeProgress(currentPage: 2, lastTimeOpened: Date(timeIntervalSince1970: 200)),
            for: makeReference(serverID: secondServerID, path: "/B/book.cbz", fileName: "book.cbz"),
            profile: secondProfile
        )

        try store.deleteSessions(for: firstProfile)

        let sessions = try makeStore(directoryURL: directoryURL).loadSessions()
        XCTAssertEqual(sessions.map(\.serverID), [secondServerID])
    }

    private func makeStore(
        directoryURL: URL,
        maximumStoredSessions: Int = 200
    ) -> RemoteReadingProgressStore {
        RemoteReadingProgressStore(
            storage: FileBackedJSONStore(
                fileName: "remote_reading_progress.json",
                storageDirectoryURL: directoryURL
            ),
            maximumStoredSessions: maximumStoredSessions
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteReadingProgressStorePersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func makeProfile(
        id: UUID,
        shareName: String
    ) -> RemoteServerProfile {
        RemoteServerProfile(
            id: id,
            name: "NAS",
            providerKind: .smb,
            host: "nas.local",
            port: 445,
            shareName: shareName,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeReference(
        serverID: UUID? = nil,
        path: String,
        fileName: String
    ) -> RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID ?? self.serverID,
            providerKind: .smb,
            shareName: "Comics",
            cacheScopeKey: nil,
            path: path,
            fileName: fileName,
            fileSize: 1024,
            modifiedAt: Date(timeIntervalSince1970: 100),
            contentKind: .file,
            pageCountHint: nil,
            coverPath: nil
        )
    }

    private func makeProgress(
        currentPage: Int,
        lastTimeOpened: Date
    ) -> ComicReadingProgress {
        ComicReadingProgress(
            currentPage: currentPage,
            pageCount: 12,
            hasBeenOpened: true,
            read: false,
            lastTimeOpened: lastTimeOpened
        )
    }
}
