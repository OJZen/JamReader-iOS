import XCTest
@testable import JamReader

final class RemoteServerProfileStorePersistenceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testLoadReturnsEmptyArrayWhenNoProfilesWereSaved() throws {
        XCTAssertEqual(try makeStore(directoryURL: try makeTemporaryDirectory()).load(), [])
    }

    func testSaveSortsProfilesByDisplayNameAndPersistsToDisk() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = makeStore(directoryURL: directoryURL)
        let zeta = makeProfile(idSuffix: "0001", name: "Zeta")
        let alpha = makeProfile(idSuffix: "0002", name: "alpha")
        let beta = makeProfile(idSuffix: "0003", name: "Beta")

        try store.save([zeta, alpha, beta])

        let reloadedProfiles = try makeStore(directoryURL: directoryURL).load()

        XCTAssertEqual(reloadedProfiles.map(\.name), ["alpha", "Beta", "Zeta"])
        XCTAssertEqual(reloadedProfiles.map(\.id), [alpha.id, beta.id, zeta.id])
    }

    private func makeStore(directoryURL: URL) -> RemoteServerProfileStore {
        RemoteServerProfileStore(
            storage: FileBackedJSONStore(
                fileName: "remote_servers.json",
                storageDirectoryURL: directoryURL
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteServerProfileStorePersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func makeProfile(idSuffix: String, name: String) -> RemoteServerProfile {
        RemoteServerProfile(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa\(idSuffix)")!,
            name: name,
            providerKind: .smb,
            host: "\(name.lowercased()).local",
            port: 445,
            shareName: "Comics",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}
