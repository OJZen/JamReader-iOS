import Foundation
import SwiftUI

enum LibraryStorageMode: String, Codable, Hashable, CaseIterable {
    case inPlace = "in_place"
    case mirrored

    var title: String {
        switch self {
        case .inPlace:
            return "In-Place"
        case .mirrored:
            return "Mirrored"
        }
    }

    var tintColor: Color {
        switch self {
        case .inPlace:
            return .green
        case .mirrored:
            return .orange
        }
    }
}
