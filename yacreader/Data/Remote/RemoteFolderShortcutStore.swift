import Foundation

final class RemoteFolderShortcutStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> [RemoteFolderShortcut] {
        let storageURL = try storageFileURL()
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([RemoteFolderShortcut].self, from: data)
    }

    func save(_ shortcuts: [RemoteFolderShortcut]) throws {
        let storageURL = try storageFileURL()
        let sortedShortcuts = shortcuts.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let data = try encoder.encode(sortedShortcuts)
        try data.write(to: storageURL, options: .atomic)
    }

    func containsShortcut(for serverID: UUID, path: String) -> Bool {
        guard let shortcuts = try? load() else {
            return false
        }

        return shortcuts.contains(where: {
            $0.serverID == serverID && $0.path == path
        })
    }

    func upsertShortcut(serverID: UUID, path: String, title: String) throws {
        var shortcuts = try load()
        let now = Date()

        if let index = shortcuts.firstIndex(where: {
            $0.serverID == serverID && $0.path == path
        }) {
            shortcuts[index].title = title
            shortcuts[index].updatedAt = now
        } else {
            shortcuts.append(
                RemoteFolderShortcut(
                    serverID: serverID,
                    path: path,
                    title: title,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try save(shortcuts)
    }

    func removeShortcut(serverID: UUID, path: String) throws {
        var shortcuts = try load()
        shortcuts.removeAll {
            $0.serverID == serverID && $0.path == path
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

    private func storageFileURL() throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("YACReader", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("remote_folder_shortcuts.json")
    }
}
