import Foundation

struct LibraryMaintenanceRecord: Codable, Equatable {
    enum Scope: String, Codable {
        case library
        case folder
        case importIndex
    }

    let libraryID: UUID
    let title: String
    let summary: LibraryScanSummary
    let scope: Scope
    let contextPath: String?
    let scannedAt: Date

    var summaryLine: String {
        "\(title) · \(summary.summaryLine)"
    }

    var detailLine: String? {
        let timestamp = relativeTimestampLine

        if let changeSummaryLine = summary.changeSummaryLine {
            return "\(timestamp) · \(changeSummaryLine)"
        }

        return timestamp
    }

    var infoLine: String {
        switch scope {
        case .library:
            return "Last full library scan"
        case .folder:
            if let contextPath, !contextPath.isEmpty {
                return "Last folder refresh · \(contextPath)"
            }

            return "Last folder refresh"
        case .importIndex:
            return "Last import indexing pass"
        }
    }

    var formattedTimestampLine: String {
        scannedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var relativeTimestampLine: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: scannedAt, relativeTo: Date()))"
    }
}
