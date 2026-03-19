import Foundation

struct RemoteFolderShortcut: Identifiable, Codable, Hashable {
    let id: UUID
    let serverID: UUID
    let path: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverID: UUID,
        path: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverID = serverID
        self.path = path
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
