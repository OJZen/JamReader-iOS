import Foundation

enum LibraryRecentWindowOption: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    static var defaultOption: LibraryRecentWindowOption {
        .sevenDays
    }

    var id: Int {
        rawValue
    }

    var dayCount: Int {
        rawValue
    }

    var title: String {
        String(localized: "\(rawValue) Days")
    }

    var subtitle: String {
        if rawValue == 7 {
            return String(localized: "Great for weekly imports.")
        }

        if rawValue == 14 {
            return String(localized: "A two-week intake window.")
        }

        if rawValue == 30 {
            return String(localized: "Good for monthly catch-up.")
        }

        return String(localized: "Use a broader backlog window.")
    }
}
