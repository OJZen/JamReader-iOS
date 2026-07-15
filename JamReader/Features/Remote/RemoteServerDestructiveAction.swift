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
            return "Clear Recent History?"
        case .clearDownloads:
            return "Clear Downloaded Comics?"
        case .clearTemporaryCache:
            return "Clear Temporary Cache?"
        case .deleteServer:
            return "Delete Server?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .clearHistory:
            return "Clear History"
        case .clearDownloads:
            return "Clear Downloads"
        case .clearTemporaryCache:
            return "Clear Temporary Cache"
        case .deleteServer:
            return "Delete Server"
        }
    }

    var message: String {
        switch self {
        case .clearHistory(let profile, let count):
            let itemText = count == 1 ? "1 recent item" : "\(count) recent items"
            return "This removes \(itemText) for \(profile.displayTitle). Downloaded comics remain on this device."
        case .clearDownloads(let profile, let count):
            let itemText = count == 1 ? "1 downloaded comic" : "\(count) downloaded comics"
            return "This deletes \(itemText) for \(profile.displayTitle) from this device. Reading history remains."
        case .clearTemporaryCache(let profile):
            return "This removes cached previews and temporary browsing data for \(profile.displayTitle). Downloaded comics remain available."
        case .deleteServer(let profile):
            return "This deletes \(profile.displayTitle), its saved credentials, downloaded comics, recent history, and saved folder shortcuts from this device."
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
