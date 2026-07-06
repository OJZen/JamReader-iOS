import Foundation

enum RemoteServerBrowsingError: LocalizedError {
    case invalidProfile(String)
    case providerIntegrationUnavailable(RemoteProviderKind)
    case unsupportedComicFile(String)
    case missingCredentials(String)
    case authenticationFailed(String)
    case shareUnavailable(String)
    case remotePathUnavailable(String)
    case accessDenied(String)
    case connectionFailed(String)
    case insecureTransportBlocked(String)
    case certificateNotTrusted(String)
    case secureConnectionFailed(String)
    case cacheMaintenanceFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason):
            return reason
        case .providerIntegrationUnavailable(let providerKind):
            return "\(providerKind.title) browsing is planned but not wired into a live network client yet."
        case .unsupportedComicFile(let fileName):
            return "\(fileName) is not a supported remote comic."
        case .missingCredentials(let reason):
            return reason
        case .authenticationFailed(let serverName):
            return "Could not sign in to \(serverName). Check the username and password, then try again."
        case .shareUnavailable(let shareName):
            return "The remote location \(shareName) is not available right now."
        case .remotePathUnavailable(let path):
            return "\(path) is no longer available on the remote server."
        case .accessDenied(let location):
            return "Access was denied for \(location)."
        case .connectionFailed(let endpoint):
            return "Could not reach \(endpoint). Check that the server is online and reachable from this device."
        case .insecureTransportBlocked(let endpoint):
            return "iOS blocked the insecure HTTP connection to \(endpoint). Use HTTPS for this WebDAV server."
        case .certificateNotTrusted(let endpoint):
            return "The TLS certificate presented by \(endpoint) is not trusted by this device."
        case .secureConnectionFailed(let endpoint):
            return "A secure connection to \(endpoint) could not be established."
        case .cacheMaintenanceFailed(let reason):
            return reason
        case .operationFailed(let reason):
            return reason
        }
    }
}

struct RemoteServerValidationIssue: Identifiable, Hashable {
    enum Severity: String, Hashable {
        case error
        case warning
    }

    let id = UUID()
    let severity: Severity
    let message: String
}

struct RemoteServerBrowserCapabilities: Hashable {
    let providerKind: RemoteProviderKind
    let supportsDirectoryBrowsing: Bool
    let supportsSingleComicOpening: Bool
}
