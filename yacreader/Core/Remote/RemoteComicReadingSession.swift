import Foundation

struct RemoteComicReadingSession: Identifiable, Codable, Hashable {
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let serverName: String
    let shareName: String
    let path: String
    let fileName: String
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
        path: String,
        fileName: String,
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
        self.path = path
        self.fileName = fileName
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
        case path
        case fileName
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
        self.path = try container.decode(String.self, forKey: .path)
        self.fileName = try container.decode(String.self, forKey: .fileName)
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
        try container.encode(path, forKey: .path)
        try container.encode(fileName, forKey: .fileName)
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
        "\(serverID.uuidString)|\(path)"
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
            path: path,
            name: fileName,
            kind: .comicFile,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    var comicFileReference: RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    private static func normalizedBookmarkPageIndices(_ indices: [Int]) -> [Int] {
        ReaderBookmarkNormalizer.normalized(indices)
    }
}
