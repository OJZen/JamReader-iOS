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
        port: Int = RemoteProviderKind.smb.defaultPort,
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

    var normalizedProviderRootIdentifier: String {
        switch providerKind {
        case .smb:
            return normalizedShareName
        case .webdav:
            return Self.normalizedAbsolutePath(normalizedShareName)
        }
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
        switch providerKind {
        case .smb:
            return "\(providerKind.rawValue)://\(normalizedHost)/\(normalizedShareName)\(normalizedBaseDirectoryPath)"
        case .webdav:
            guard let webDAVBaseURL else {
                return "\(providerKind.rawValue)://\(normalizedHost)\(normalizedProviderRootIdentifier)\(normalizedBaseDirectoryPath)"
            }

            guard !normalizedBaseDirectoryPath.isEmpty else {
                return webDAVBaseURL.absoluteString
            }

            var components = URLComponents(url: webDAVBaseURL, resolvingAgainstBaseURL: false)
            components?.path = Self.joinAbsolutePaths(
                webDAVBaseURL.path,
                normalizedBaseDirectoryPath
            )
            return components?.url?.absoluteString ?? webDAVBaseURL.absoluteString
        }
    }

    var usesDefaultPort: Bool {
        switch providerKind {
        case .smb:
            return port == RemoteProviderKind.smb.defaultPort
        case .webdav:
            return port == defaultPortForResolvedWebDAVScheme
        }
    }

    var webDAVBaseURL: URL? {
        guard providerKind == .webdav else {
            return nil
        }

        let trimmedHost = normalizedHost
        guard !trimmedHost.isEmpty else {
            return nil
        }

        let seededHost = trimmedHost.contains("://")
            ? trimmedHost
            : "\(resolvedWebDAVScheme)://\(trimmedHost)"

        guard var components = URLComponents(string: seededHost),
              components.host != nil else {
            return nil
        }

        let hostPath = Self.normalizedAbsolutePath(
            components.percentEncodedPath.removingPercentEncoding ?? components.path
        )
        let collectionPath = Self.joinAbsolutePaths(hostPath, normalizedProviderRootIdentifier)
        components.path = collectionPath.isEmpty ? "/" : collectionPath

        if port == defaultPortForResolvedWebDAVScheme {
            components.port = nil
        } else {
            components.port = port
        }

        return components.url
    }

    var resolvedWebDAVScheme: String {
        guard providerKind == .webdav else {
            return "https"
        }

        if let components = URLComponents(string: normalizedHost),
           let scheme = components.scheme?.lowercased(),
           !scheme.isEmpty {
            return scheme
        }

        return port == 80 ? "http" : "https"
    }

    var defaultPortForResolvedWebDAVScheme: Int {
        resolvedWebDAVScheme == "http" ? 80 : 443
    }

    var endpointDisplayHost: String {
        switch providerKind {
        case .smb:
            return usesDefaultPort ? normalizedHost : "\(normalizedHost):\(port)"
        case .webdav:
            guard let webDAVBaseURL,
                  let host = webDAVBaseURL.host else {
                return normalizedHost
            }

            if let resolvedPort = webDAVBaseURL.port {
                return "\(host):\(resolvedPort)"
            }

            return host
        }
    }

    var providerRootDisplayPath: String {
        switch providerKind {
        case .smb:
            let shareComponent = normalizedShareName.isEmpty ? "" : "/\(normalizedShareName)"
            let combinedPath = "\(shareComponent)\(normalizedBaseDirectoryPath)"
            return combinedPath.isEmpty ? "/" : combinedPath
        case .webdav:
            let combinedPath = Self.joinAbsolutePaths(
                normalizedProviderRootIdentifier,
                normalizedBaseDirectoryPath
            )
            return combinedPath.isEmpty ? "/" : combinedPath
        }
    }

    var remoteScopeKey: String {
        "\(providerKind.rawValue)|\(normalizedProviderRootIdentifier)"
    }

    func matchesRemoteScope(
        providerKind: RemoteProviderKind,
        providerRootIdentifier: String
    ) -> Bool {
        self.providerKind == providerKind
            && normalizedProviderRootIdentifier == providerRootIdentifier
    }

    private static func normalizedAbsolutePath(_ rawPath: String) -> String {
        let collapsedPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !collapsedPath.isEmpty else {
            return ""
        }

        return "/" + collapsedPath
    }

    private static func joinAbsolutePaths(_ lhs: String, _ rhs: String) -> String {
        let joined = [lhs, rhs]
            .flatMap { value in
                value.split(separator: "/").map(String.init)
            }
            .joined(separator: "/")

        guard !joined.isEmpty else {
            return ""
        }

        return "/" + joined
    }
}
