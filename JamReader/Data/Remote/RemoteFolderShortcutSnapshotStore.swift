import Foundation
import os

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
    private let logger = AppLog.remote

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

        var missingProfileCount = 0
        var profileMismatchCount = 0
        let entries = shortcuts.compactMap { shortcut -> RemoteResolvedFolderShortcut? in
            guard let profile = profilesByID[shortcut.serverID] else {
                missingProfileCount += 1
                return nil
            }

            guard shortcut.matches(profile: profile) else {
                profileMismatchCount += 1
                return nil
            }

            return RemoteResolvedFolderShortcut(
                shortcut: shortcut,
                profile: profile
            )
        }

        let filteredCount = missingProfileCount + profileMismatchCount
        if filteredCount > 0 {
            logger.debug(
                "Remote folder shortcuts snapshot filtered total=\(shortcuts.count, privacy: .public) visible=\(entries.count, privacy: .public) missingProfile=\(missingProfileCount, privacy: .public) profileMismatch=\(profileMismatchCount, privacy: .public)"
            )
        }
        return entries
    }
}
