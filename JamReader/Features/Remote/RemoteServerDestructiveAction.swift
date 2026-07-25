import Foundation

enum RemoteServerDestructiveAction: Identifiable {
    case clearHistory(RemoteServerProfile, count: Int)
    case clearDownloads(RemoteServerProfile, count: Int)
    case clearTemporaryCache(RemoteServerProfile)
    case deleteServer(RemoteServerProfile)

    var id: String {
        "\(kindID):\(profile.id.uuidString)"
    }

    var title: String {
        switch self {
        case .clearHistory:
            return String(localized: "Clear Recent History?")
        case .clearDownloads:
            return String(localized: "Clear Downloaded Comics?")
        case .clearTemporaryCache:
            return String(localized: "Clear Temporary Cache?")
        case .deleteServer:
            return String(localized: "Delete Server?")
        }
    }

    var buttonTitle: String {
        switch self {
        case .clearHistory:
            return String(localized: "Clear History")
        case .clearDownloads:
            return String(localized: "Clear Downloads")
        case .clearTemporaryCache:
            return String(localized: "Clear Temporary Cache")
        case .deleteServer:
            return String(localized: "Delete Server")
        }
    }

    var message: String {
        switch self {
        case .clearHistory(let profile, let count):
            if count == 1 {
                return String(localized: "This removes 1 recent item for \(profile.displayTitle). Downloaded comics remain on this device.")
            }
            return String(localized: "This removes \(count) recent items for \(profile.displayTitle). Downloaded comics remain on this device.")
        case .clearDownloads(let profile, let count):
            if count == 1 {
                return String(localized: "This deletes 1 downloaded comic for \(profile.displayTitle) from this device. Reading history remains.")
            }
            return String(localized: "This deletes \(count) downloaded comics for \(profile.displayTitle) from this device. Reading history remains.")
        case .clearTemporaryCache(let profile):
            return String(localized: "This removes cached previews and temporary browsing data for \(profile.displayTitle). Downloaded comics remain available.")
        case .deleteServer(let profile):
            return String(localized: "This deletes \(profile.displayTitle), its saved credentials, downloaded comics, recent history, and saved folder shortcuts from this device.")
        }
    }

    var profile: RemoteServerProfile {
        switch self {
        case .clearHistory(let profile, _),
             .clearDownloads(let profile, _),
             .clearTemporaryCache(let profile),
             .deleteServer(let profile):
            return profile
        }
    }

    private var kindID: String {
        switch self {
        case .clearHistory:
            return "history"
        case .clearDownloads:
            return "downloads"
        case .clearTemporaryCache:
            return "temporary-cache"
        case .deleteServer:
            return "delete"
        }
    }
}
