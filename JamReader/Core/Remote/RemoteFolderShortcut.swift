import Foundation

struct RemoteFolderShortcut: Identifiable, Codable, Hashable {
    let id: UUID
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let providerRootIdentifier: String
    let path: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        serverID: UUID,
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String,
        path: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serverID = serverID
        self.providerKind = providerKind
        self.providerRootIdentifier = providerRootIdentifier
        self.path = path
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case serverID
        case providerKind
        case providerRootIdentifier
        case path
        case title
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        serverID = try container.decode(UUID.self, forKey: .serverID)
        providerKind = try container.decodeIfPresent(RemoteProviderKind.self, forKey: .providerKind) ?? .smb
        providerRootIdentifier = try container.decodeIfPresent(String.self, forKey: .providerRootIdentifier) ?? ""
        path = try container.decode(String.self, forKey: .path)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func matches(profile: RemoteServerProfile) -> Bool {
        guard serverID == profile.id else {
            return false
        }

        if providerRootIdentifier.isEmpty {
            return providerKind == profile.providerKind
        }

        return profile.matchesRemoteScope(
            providerKind: providerKind,
            providerRootIdentifier: providerRootIdentifier
        )
    }
}
