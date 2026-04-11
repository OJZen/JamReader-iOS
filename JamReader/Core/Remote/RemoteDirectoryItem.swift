import Foundation

enum RemoteDirectoryItemKind: String, Hashable {
    case directory
    case comicFile
    case comicDirectory
    case unsupportedFile
}

enum RemoteComicReferenceKind: String, Codable, Hashable {
    case file
    case imageDirectory
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
    let pageCountHint: Int?
    let coverPath: String?
    let previewItems: [RemoteDirectoryItem]

    nonisolated var id: String {
        "\(serverID.uuidString)|\(providerKind.rawValue)|\(shareName)|\(cacheScopeKey)|\(path)"
    }

    nonisolated var isDirectory: Bool {
        kind == .directory
    }

    nonisolated var isComicDirectory: Bool {
        kind == .comicDirectory
    }

    nonisolated var canOpenAsComic: Bool {
        kind == .comicFile || kind == .comicDirectory
    }

    nonisolated var comicReferenceKind: RemoteComicReferenceKind? {
        switch kind {
        case .comicFile:
            return .file
        case .comicDirectory:
            return .imageDirectory
        case .directory, .unsupportedFile:
            return nil
        }
    }

    nonisolated var fileExtension: String {
        URL(fileURLWithPath: name).pathExtension.lowercased()
    }

    nonisolated var isPDFDocument: Bool {
        !isComicDirectory && fileExtension == "pdf"
    }

    nonisolated var titleSystemImageName: String {
        if isDirectory {
            return "folder.fill"
        }

        if canOpenAsComic {
            return "book.closed.fill"
        }

        return "doc.fill"
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
    let contentKind: RemoteComicReferenceKind
    let pageCountHint: Int?
    let coverPath: String?

    nonisolated var id: String {
        "\(serverID.uuidString)|\(providerKind.rawValue)|\(shareName)|\(cacheScopeKey ?? "legacy")|\(contentKind.rawValue)|\(path)"
    }

    nonisolated var isImageDirectoryComic: Bool {
        contentKind == .imageDirectory
    }

    nonisolated var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }

    nonisolated var isPDFDocument: Bool {
        contentKind == .file && fileExtension == "pdf"
    }
}
