import Foundation
import SwiftUI

enum RemoteProviderKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case smb

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .smb:
            return "SMB"
        }
    }

    var systemImage: String {
        switch self {
        case .smb:
            return "server.rack"
        }
    }

    var tintColor: Color {
        switch self {
        case .smb:
            return .blue
        }
    }
}
