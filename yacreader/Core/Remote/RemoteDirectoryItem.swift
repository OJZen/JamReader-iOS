import Foundation

enum RemoteDirectoryItemKind: String, Hashable {
    case directory
    case comicFile
    case unsupportedFile
}

struct RemoteDirectoryItem: Identifiable, Hashable {
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let shareName: String
    let cacheScopeKey: String
    let path: String
    let name: String
    let kind: RemoteDirectoryItemKind
    let fileSize: Int64?
    let modifiedAt: Date?

    var id: String {
        "\(serverID.uuidString)|\(providerKind.rawValue)|\(shareName)|\(cacheScopeKey)|\(path)"
    }

    var isDirectory: Bool {
        kind == .directory
    }

    var canOpenAsComic: Bool {
        kind == .comicFile
    }
}

struct RemoteComicFileReference: Identifiable, Hashable {
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let shareName: String
    let cacheScopeKey: String?
    let path: String
    let fileName: String
    let fileSize: Int64?
    let modifiedAt: Date?

    var id: String {
        "\(serverID.uuidString)|\(providerKind.rawValue)|\(shareName)|\(cacheScopeKey ?? "legacy")|\(path)"
    }
}
