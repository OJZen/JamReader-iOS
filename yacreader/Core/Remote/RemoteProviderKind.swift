import Foundation
import SwiftUI

enum RemoteProviderKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case smb
    case webdav

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .smb:
            return "SMB"
        case .webdav:
            return "WebDAV"
        }
    }

    var systemImage: String {
        switch self {
        case .smb:
            return "server.rack"
        case .webdav:
            return "globe"
        }
    }

    var tintColor: Color {
        switch self {
        case .smb:
            return .blue
        case .webdav:
            return .indigo
        }
    }

    var defaultPort: Int {
        switch self {
        case .smb:
            return 445
        case .webdav:
            return 443
        }
    }
}
