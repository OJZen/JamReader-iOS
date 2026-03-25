import Foundation

final class RemoteFolderShortcutStore {
    private let storage: FileBackedJSONStore

    init(fileManager: FileManager = .default) {
        self.storage = FileBackedJSONStore(fileName: "remote_folder_shortcuts.json", fileManager: fileManager)
    }

    func load() throws -> [RemoteFolderShortcut] {
        try storage.load([RemoteFolderShortcut].self) ?? []
    }

    func save(_ shortcuts: [RemoteFolderShortcut]) throws {
        let sortedShortcuts = shortcuts.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        try storage.save(sortedShortcuts)
    }

    func containsShortcut(
        for serverID: UUID,
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String,
        path: String
    ) -> Bool {
        guard let shortcuts = try? load() else {
            return false
        }

        return shortcuts.contains(where: {
            $0.serverID == serverID
                && $0.providerKind == providerKind
                && $0.providerRootIdentifier == providerRootIdentifier
                && $0.path == path
        })
    }

    func upsertShortcut(
        serverID: UUID,
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String,
        path: String,
        title: String
    ) throws {
        var shortcuts = try load()
        let now = Date()

        if let index = shortcuts.firstIndex(where: {
            $0.serverID == serverID
                && $0.providerKind == providerKind
                && $0.providerRootIdentifier == providerRootIdentifier
                && $0.path == path
        }) {
            shortcuts[index].title = title
            shortcuts[index].updatedAt = now
        } else {
            shortcuts.append(
                RemoteFolderShortcut(
                    serverID: serverID,
                    providerKind: providerKind,
                    providerRootIdentifier: providerRootIdentifier,
                    path: path,
                    title: title,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try save(shortcuts)
    }

    func removeShortcut(
        serverID: UUID,
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String,
        path: String
    ) throws {
        var shortcuts = try load()
        shortcuts.removeAll {
            $0.serverID == serverID
                && $0.providerKind == providerKind
                && $0.providerRootIdentifier == providerRootIdentifier
                && $0.path == path
        }
        try save(shortcuts)
    }

    func removeShortcut(id: UUID) throws {
        var shortcuts = try load()
        shortcuts.removeAll { $0.id == id }
        try save(shortcuts)
    }

    func renameShortcut(id: UUID, title: String) throws {
        var shortcuts = try load()
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else {
            return
        }

        shortcuts[index].title = title
        shortcuts[index].updatedAt = Date()
        try save(shortcuts)
    }

    func removeShortcuts(for serverID: UUID) throws {
        var shortcuts = try load()
        shortcuts.removeAll { $0.serverID == serverID }
        try save(shortcuts)
    }

    func removeShortcuts(
        for serverID: UUID,
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String
    ) throws {
        var shortcuts = try load()
        shortcuts.removeAll {
            $0.serverID == serverID
                && $0.providerKind == providerKind
                && $0.providerRootIdentifier == providerRootIdentifier
        }
        try save(shortcuts)
    }

}
