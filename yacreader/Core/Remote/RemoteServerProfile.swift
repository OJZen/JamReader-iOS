import Foundation

struct RemoteServerProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var providerKind: RemoteProviderKind
    var host: String
    var port: Int
    var shareName: String
    var baseDirectoryPath: String
    var authenticationMode: RemoteServerAuthenticationMode
    var username: String
    var passwordReferenceKey: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        providerKind: RemoteProviderKind = .smb,
        host: String,
        port: Int = 445,
        shareName: String,
        baseDirectoryPath: String = "",
        authenticationMode: RemoteServerAuthenticationMode = .usernamePassword,
        username: String = "",
        passwordReferenceKey: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerKind = providerKind
        self.host = host
        self.port = port
        self.shareName = shareName
        self.baseDirectoryPath = baseDirectoryPath
        self.authenticationMode = authenticationMode
        self.username = username
        self.passwordReferenceKey = passwordReferenceKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedShareName: String {
        shareName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedBaseDirectoryPath: String {
        let trimmedPath = baseDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return ""
        }

        let collapsedPath = trimmedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return collapsedPath.isEmpty ? "" : "/" + collapsedPath
    }

    var connectionDisplayPath: String {
        "\(providerKind.rawValue)://\(normalizedHost)/\(normalizedShareName)\(normalizedBaseDirectoryPath)"
    }

    var usesDefaultPort: Bool {
        switch providerKind {
        case .smb:
            return port == 445
        }
    }
}
