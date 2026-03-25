import Foundation

final class RemoteServerProfileStore {
    private let storage: FileBackedJSONStore

    init(fileManager: FileManager = .default) {
        self.storage = FileBackedJSONStore(fileName: "remote_servers.json", fileManager: fileManager)
    }

    func load() throws -> [RemoteServerProfile] {
        try storage.load([RemoteServerProfile].self) ?? []
    }

    func save(_ profiles: [RemoteServerProfile]) throws {
        let sortedProfiles = profiles.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        try storage.save(sortedProfiles)
    }
}
