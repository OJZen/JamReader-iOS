import Foundation

struct RemoteResolvedFolderShortcut: Identifiable, Hashable {
    let shortcut: RemoteFolderShortcut
    let profile: RemoteServerProfile

    var id: UUID {
        shortcut.id
    }
}

final class RemoteFolderShortcutSnapshotStore {
    private let remoteServerProfileStore: RemoteServerProfileStore
    private let remoteFolderShortcutStore: RemoteFolderShortcutStore

    init(
        remoteServerProfileStore: RemoteServerProfileStore,
        remoteFolderShortcutStore: RemoteFolderShortcutStore
    ) {
        self.remoteServerProfileStore = remoteServerProfileStore
        self.remoteFolderShortcutStore = remoteFolderShortcutStore
    }

    func loadEntries() throws -> [RemoteResolvedFolderShortcut] {
        let profiles = try remoteServerProfileStore.load()
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let shortcuts = try remoteFolderShortcutStore.load()

        return shortcuts.compactMap { shortcut -> RemoteResolvedFolderShortcut? in
            guard let profile = profilesByID[shortcut.serverID],
                  shortcut.matches(profile: profile) else {
                return nil
            }

            return RemoteResolvedFolderShortcut(
                shortcut: shortcut,
                profile: profile
            )
        }
    }
}
