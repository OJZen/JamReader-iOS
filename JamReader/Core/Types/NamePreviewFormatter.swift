import Foundation

enum NamePreviewFormatter {
    static func preview(from names: [String], limit: Int = 3) -> String {
        let uniqueSortedNames = Array(Set(names)).sorted()
        guard uniqueSortedNames.count > limit else {
            return uniqueSortedNames.joined(separator: ", ")
        }

        let preview = uniqueSortedNames.prefix(limit).joined(separator: ", ")
        let remainingCount = uniqueSortedNames.count - limit
        return String(localized: "\(preview), +\(remainingCount) more")
    }
}
