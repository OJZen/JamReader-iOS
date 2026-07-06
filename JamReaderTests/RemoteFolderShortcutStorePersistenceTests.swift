import XCTest
@testable import JamReader

final class RemoteFolderShortcutStorePersistenceTests: XCTestCase {
    private let serverID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testLoadReturnsEmptyArrayWhenNoShortcutsWereSaved() throws {
        XCTAssertEqual(try makeShortcutStore(directoryURL: try makeTemporaryDirectory()).load(), [])
    }

    func testSaveSortsByUpdatedDateThenTitleAndPersistsToDisk() throws {
        let directoryURL = try makeTemporaryDirectory()
        let older = makeShortcut(
            idSuffix: "0001",
            path: "/Older",
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let alpha = makeShortcut(
            idSuffix: "0002",
            path: "/Alpha",
            title: "Alpha",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let zeta = makeShortcut(
            idSuffix: "0003",
            path: "/Zeta",
            title: "Zeta",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try makeShortcutStore(directoryURL: directoryURL).save([older, zeta, alpha])

        XCTAssertEqual(
            try makeShortcutStore(directoryURL: directoryURL).load().map(\.title),
            ["Alpha", "Zeta", "Older"]
        )
    }

    func testUpsertUpdatesExistingShortcutInsteadOfDuplicatingIt() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = makeShortcutStore(directoryURL: directoryURL)

        try store.upsertShortcut(
            serverID: serverID,
            providerKind: .smb,
            providerRootIdentifier: "Comics",
            path: "/Series",
            title: "Old Name"
        )
        try store.upsertShortcut(
            serverID: serverID,
            providerKind: .smb,
            providerRootIdentifier: "Comics",
            path: "/Series",
            title: "New Name"
        )

        let shortcuts = try makeShortcutStore(directoryURL: directoryURL).load()
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertEqual(shortcuts.first?.title, "New Name")
        XCTAssertTrue(
            store.containsShortcut(
                for: serverID,
                providerKind: .smb,
                providerRootIdentifier: "Comics",
                path: "/Series"
            )
        )
    }

    func testRemoveShortcutsByServerScope() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = makeShortcutStore(directoryURL: directoryURL)
        let otherServerID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        try store.save([
            makeShortcut(idSuffix: "0001", path: "/A", title: "A"),
            makeShortcut(idSuffix: "0002", serverID: otherServerID, path: "/B", title: "B"),
            makeShortcut(idSuffix: "0003", providerRootIdentifier: "Archive", path: "/C", title: "C")
        ])

        try store.removeShortcuts(
            for: serverID,
            providerKind: .smb,
            providerRootIdentifier: "Comics"
        )

        XCTAssertEqual(
            try makeShortcutStore(directoryURL: directoryURL).load().map(\.title),
            ["B", "C"]
        )
    }

    func testSnapshotStoreFiltersShortcutsWithoutMatchingProfiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        let profileStore = makeProfileStore(directoryURL: directoryURL)
        let shortcutStore = makeShortcutStore(directoryURL: directoryURL)
        let profile = makeProfile(id: serverID, shareName: "Comics")
        let otherServerID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

        try profileStore.save([profile])
        try shortcutStore.save([
            makeShortcut(idSuffix: "0001", path: "/Series", title: "Visible"),
            makeShortcut(idSuffix: "0002", serverID: otherServerID, path: "/Other", title: "Missing Server"),
            makeShortcut(idSuffix: "0003", providerRootIdentifier: "Archive", path: "/Archive", title: "Wrong Share")
        ])

        let entries = try RemoteFolderShortcutSnapshotStore(
            remoteServerProfileStore: profileStore,
            remoteFolderShortcutStore: shortcutStore
        ).loadEntries()

        XCTAssertEqual(entries.map(\.shortcut.title), ["Visible"])
        XCTAssertEqual(entries.first?.profile.id, profile.id)
    }

    private func makeShortcutStore(directoryURL: URL) -> RemoteFolderShortcutStore {
        RemoteFolderShortcutStore(
            storage: FileBackedJSONStore(
                fileName: "remote_folder_shortcuts.json",
                storageDirectoryURL: directoryURL
            )
        )
    }

    private func makeProfileStore(directoryURL: URL) -> RemoteServerProfileStore {
        RemoteServerProfileStore(
            storage: FileBackedJSONStore(
                fileName: "remote_servers.json",
                storageDirectoryURL: directoryURL
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteFolderShortcutStorePersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func makeShortcut(
        idSuffix: String,
        serverID: UUID? = nil,
        providerRootIdentifier: String = "Comics",
        path: String,
        title: String,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> RemoteFolderShortcut {
        RemoteFolderShortcut(
            id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeee\(idSuffix)")!,
            serverID: serverID ?? self.serverID,
            providerKind: .smb,
            providerRootIdentifier: providerRootIdentifier,
            path: path,
            title: title,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: updatedAt
        )
    }

    private func makeProfile(id: UUID, shareName: String) -> RemoteServerProfile {
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
}
