import Foundation

/// Where continue reading appears: aggregated on the library home (default)
/// or in each library's root. It is never shown in both places.
enum ContinueReadingPlacement: String, CaseIterable, Identifiable {
    case libraryHome
    case insideLibraries

    static let defaultValue: ContinueReadingPlacement = .libraryHome

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .libraryHome:
            return String(localized: "Library Home")
        case .insideLibraries:
            return String(localized: "Inside Each Library")
        }
    }
}
