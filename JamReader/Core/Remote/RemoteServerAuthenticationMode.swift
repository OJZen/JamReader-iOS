import Foundation

enum RemoteServerAuthenticationMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case guest
    case usernamePassword = "username_password"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .guest:
            return "Guest"
        case .usernamePassword:
            return "Username & Password"
        }
    }

    var requiresUsername: Bool {
        switch self {
        case .guest:
            return false
        case .usernamePassword:
            return true
        }
    }

    var requiresPassword: Bool {
        switch self {
        case .guest:
            return false
        case .usernamePassword:
            return true
        }
    }
}
