import Foundation

enum LibraryLabelColor: Int, CaseIterable, Identifiable, Hashable {
    case red = 1
    case orange
    case yellow
    case green
    case cyan
    case blue
    case violet
    case purple
    case pink
    case white
    case light
    case dark

    var id: Int {
        rawValue
    }

    init(databaseColorName: String?, ordering: Int64?) {
        if let ordering, let color = LibraryLabelColor(rawValue: Int(ordering)) {
            self = color
            return
        }

        let normalizedName = databaseColorName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedName {
        case "red":
            self = .red
        case "orange":
            self = .orange
        case "yellow":
            self = .yellow
        case "green":
            self = .green
        case "cyan":
            self = .cyan
        case "blue":
            self = .blue
        case "violet":
            self = .violet
        case "purple":
            self = .purple
        case "pink":
            self = .pink
        case "white":
            self = .white
        case "light":
            self = .light
        case "dark":
            self = .dark
        default:
            self = .blue
        }
    }

    var databaseName: String {
        switch self {
        case .red:
            return "red"
        case .orange:
            return "orange"
        case .yellow:
            return "yellow"
        case .green:
            return "green"
        case .cyan:
            return "cyan"
        case .blue:
            return "blue"
        case .violet:
            return "violet"
        case .purple:
            return "purple"
        case .pink:
            return "pink"
        case .white:
            return "white"
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }

    var displayName: String {
        switch self {
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .cyan:
            return "Cyan"
        case .blue:
            return "Blue"
        case .violet:
            return "Violet"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .white:
            return "White"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var hexColor: String {
        switch self {
        case .red:
            return "#FD777C"
        case .orange:
            return "#FEBF34"
        case .yellow:
            return "#F5E934"
        case .green:
            return "#B6E525"
        case .cyan:
            return "#9FFFDD"
        case .blue:
            return "#82C7FF"
        case .violet:
            return "#8286FF"
        case .purple:
            return "#E39FFF"
        case .pink:
            return "#FF9FDD"
        case .white:
            return "#E3E3E3"
        case .light:
            return "#C8C8C8"
        case .dark:
            return "#ABABAB"
        }
    }
}
