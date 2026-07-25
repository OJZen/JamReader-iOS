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
        case .invalidProfile:
            return String(localized: "The remote server profile is incomplete.")
        case .providerIntegrationUnavailable(let providerKind):
            return String(localized: "\(providerKind.title) browsing is planned but not wired into a live network client yet.")
        case .unsupportedComicFile(let fileName):
            return String(localized: "\(fileName) is not a supported remote comic.")
        case .missingCredentials:
            return String(localized: "The saved credentials for this server are unavailable. Edit the server and save them again.")
        case .authenticationFailed(let serverName):
            return String(localized: "Could not sign in to \(serverName). Check the username and password, then try again.")
        case .shareUnavailable(let shareName):
            return String(localized: "The remote location \(shareName) is not available right now.")
        case .remotePathUnavailable(let path):
            return String(localized: "\(path) is no longer available on the remote server.")
        case .accessDenied(let location):
            return String(localized: "Access was denied for \(location).")
        case .connectionFailed(let endpoint):
            return String(localized: "Could not reach \(endpoint). Check that the server is online and reachable from this device.")
        case .insecureTransportBlocked(let endpoint):
            return String(localized: "iOS blocked the insecure HTTP connection to \(endpoint). Use HTTPS for this WebDAV server.")
        case .certificateNotTrusted(let endpoint):
            return String(localized: "The TLS certificate presented by \(endpoint) is not trusted by this device.")
        case .secureConnectionFailed(let endpoint):
            return String(localized: "A secure connection to \(endpoint) could not be established.")
        case .cacheMaintenanceFailed:
            return String(localized: "The remote cache could not be updated. Close any open comic and try again.")
        case .operationFailed:
            return String(localized: "The remote operation could not be completed.")
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
