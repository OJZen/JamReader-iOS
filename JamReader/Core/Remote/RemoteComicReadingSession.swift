import Foundation

struct RemoteComicReadingSession: Identifiable, Codable, Hashable {
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let serverName: String
    let shareName: String
    let cacheScopeKey: String?
    let path: String
    let fileName: String
    let contentKind: RemoteComicReferenceKind
    let pageCount: Int?
    let currentPage: Int
    let hasBeenOpened: Bool
    let read: Bool
    let lastTimeOpened: Date
    let fileSize: Int64?
    let modifiedAt: Date?
    let bookmarkPageIndices: [Int]

    init(
        serverID: UUID,
        providerKind: RemoteProviderKind,
        serverName: String,
        shareName: String,
        cacheScopeKey: String? = nil,
        path: String,
        fileName: String,
        contentKind: RemoteComicReferenceKind = .file,
        pageCount: Int?,
        currentPage: Int,
        hasBeenOpened: Bool,
        read: Bool,
        lastTimeOpened: Date,
        fileSize: Int64?,
        modifiedAt: Date?,
        bookmarkPageIndices: [Int] = []
    ) {
        self.serverID = serverID
        self.providerKind = providerKind
        self.serverName = serverName
        self.shareName = shareName
        self.cacheScopeKey = cacheScopeKey
        self.path = path
        self.fileName = fileName
        self.contentKind = contentKind
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.hasBeenOpened = hasBeenOpened
        self.read = read
        self.lastTimeOpened = lastTimeOpened
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.bookmarkPageIndices = Self.normalizedBookmarkPageIndices(bookmarkPageIndices)
    }

    private enum CodingKeys: String, CodingKey {
        case serverID
        case providerKind
        case serverName
        case shareName
        case cacheScopeKey
        case path
        case fileName
        case contentKind
        case pageCount
        case currentPage
        case hasBeenOpened
        case read
        case lastTimeOpened
        case fileSize
        case modifiedAt
        case bookmarkPageIndices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serverID = try container.decode(UUID.self, forKey: .serverID)
        self.providerKind = try container.decode(RemoteProviderKind.self, forKey: .providerKind)
        self.serverName = try container.decode(String.self, forKey: .serverName)
        self.shareName = try container.decode(String.self, forKey: .shareName)
        self.cacheScopeKey = try container.decodeIfPresent(String.self, forKey: .cacheScopeKey)
        self.path = try container.decode(String.self, forKey: .path)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.contentKind = try container.decodeIfPresent(RemoteComicReferenceKind.self, forKey: .contentKind) ?? .file
        self.pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        self.currentPage = try container.decode(Int.self, forKey: .currentPage)
        self.hasBeenOpened = try container.decode(Bool.self, forKey: .hasBeenOpened)
        self.read = try container.decode(Bool.self, forKey: .read)
        self.lastTimeOpened = try container.decode(Date.self, forKey: .lastTimeOpened)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        self.bookmarkPageIndices = Self.normalizedBookmarkPageIndices(
            try container.decodeIfPresent([Int].self, forKey: .bookmarkPageIndices) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverID, forKey: .serverID)
        try container.encode(providerKind, forKey: .providerKind)
        try container.encode(serverName, forKey: .serverName)
        try container.encode(shareName, forKey: .shareName)
        try container.encodeIfPresent(cacheScopeKey, forKey: .cacheScopeKey)
        try container.encode(path, forKey: .path)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encode(currentPage, forKey: .currentPage)
        try container.encode(hasBeenOpened, forKey: .hasBeenOpened)
        try container.encode(read, forKey: .read)
        try container.encode(lastTimeOpened, forKey: .lastTimeOpened)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try container.encode(bookmarkPageIndices, forKey: .bookmarkPageIndices)
    }

    var id: String {
        "\(serverID.uuidString)|\(providerKind.rawValue)|\(shareName)|\(cacheScopeKey ?? "legacy")|\(contentKind.rawValue)|\(path)"
    }

    var displayName: String {
        fileName
    }

    var progressText: String {
        if read {
            return "Read"
        }

        if hasBeenOpened, currentPage > 0 {
            if let pageCount, pageCount > 0 {
                return "Page \(currentPage) / \(pageCount)"
            }

            return "Page \(currentPage)"
        }

        if let pageCount, pageCount > 0 {
            return "\(pageCount) pages"
        }

        return "Unread"
    }

    var pageIndex: Int {
        max(0, currentPage - 1)
    }

    var directoryItem: RemoteDirectoryItem {
        RemoteDirectoryItem(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey ?? "legacy",
            path: path,
            name: fileName,
            kind: contentKind == .imageDirectory ? .comicDirectory : .comicFile,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            pageCountHint: pageCount,
            coverPath: nil,
            previewItems: []
        )
    }

    var parentDirectoryPath: String {
        let components = path
            .split(separator: "/")
            .map(String.init)

        guard components.count > 1 else {
            return ""
        }

        return "/" + components.dropLast().joined(separator: "/")
    }

    var comicFileReference: RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            contentKind: contentKind,
            pageCountHint: pageCount,
            coverPath: nil
        )
    }

    func resolvedComicFileReference(for profile: RemoteServerProfile) -> RemoteComicFileReference {
        guard cacheScopeKey == nil,
              matches(profile: profile) else {
            return comicFileReference
        }

        return RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: profile.remoteCacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            contentKind: contentKind,
            pageCountHint: pageCount,
            coverPath: nil
        )
    }

    func matches(profile: RemoteServerProfile) -> Bool {
        guard serverID == profile.id,
              profile.matchesRemoteScope(
                  providerKind: providerKind,
                  providerRootIdentifier: shareName
              ) else {
            return false
        }

        if let cacheScopeKey {
            return cacheScopeKey == profile.remoteCacheScopeKey
        }

        return true
    }

    func matches(reference: RemoteComicFileReference) -> Bool {
        guard serverID == reference.serverID,
              providerKind == reference.providerKind,
              shareName == reference.shareName,
              contentKind == reference.contentKind,
              path == reference.path else {
            return false
        }

        if let referenceCacheScopeKey = reference.cacheScopeKey {
            guard let cacheScopeKey else {
                return true
            }

            return cacheScopeKey == referenceCacheScopeKey
        }

        return true
    }

    private static func normalizedBookmarkPageIndices(_ indices: [Int]) -> [Int] {
        ReaderBookmarkNormalizer.normalized(indices)
    }
}
