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

    var localizedTitle: String {
        switch title {
        case "Library Ready":
            return String(localized: "Library Ready")
        case "Library Refreshed":
            return String(localized: "Library Refreshed")
        case "Folder Refreshed":
            return String(localized: "Folder Refreshed")
        case "Library Updated":
            return String(localized: "Library Updated")
        default:
            return title
        }
    }

    var summaryLine: String {
        String(localized: "\(localizedTitle) · \(summary.summaryLine)")
    }

    var detailLine: String? {
        let timestamp = relativeTimestampLine

        if let changeSummaryLine = summary.changeSummaryLine {
            return String(localized: "\(timestamp) · \(changeSummaryLine)")
        }

        return timestamp
    }

    var infoLine: String {
        switch scope {
        case .library:
            return String(localized: "Last full library scan")
        case .folder:
            if let contextPath, !contextPath.isEmpty {
                return String(localized: "Last folder refresh · \(contextPath)")
            }

            return String(localized: "Last folder refresh")
        case .importIndex:
            return String(localized: "Last import indexing pass")
        }
    }

    var formattedTimestampLine: String {
        scannedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var relativeTimestampLine: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTimestamp = formatter.localizedString(for: scannedAt, relativeTo: Date())
        return String(localized: "Updated \(relativeTimestamp)")
    }
}
