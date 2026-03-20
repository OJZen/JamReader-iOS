import Combine
import Foundation

@MainActor
final class BrowseHomeViewModel: ObservableObject {
    typealias ShortcutEntry = RemoteResolvedFolderShortcut

    @Published private(set) var profiles: [RemoteServerProfile] = []
    @Published private(set) var sessions: [RemoteComicReadingSession] = []
    @Published private(set) var offlineEntries: [RemoteOfflineComicEntry] = []
    @Published private(set) var shortcutEntries: [ShortcutEntry] = []
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
    @Published private(set) var thumbnailCacheSummary: RemoteThumbnailCacheSummary = .empty
    @Published private(set) var isLoading = false
    @Published var alert: BrowseHomeAlert?

    private let remoteFolderShortcutSnapshotStore: RemoteFolderShortcutSnapshotStore
    private let remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.remoteFolderShortcutSnapshotStore = dependencies.remoteFolderShortcutSnapshotStore
        self.remoteOfflineLibrarySnapshotStore = dependencies.remoteOfflineLibrarySnapshotStore
    }

    var summaryTitle: String {
        switch profiles.count {
        case 0:
            return "Browse remote comics"
        case 1:
            return "1 SMB server ready"
        default:
            return "\(profiles.count) SMB servers ready"
        }
    }

    var summaryText: String {
        if profiles.isEmpty {
            return "Add an SMB server, browse remote folders, open comics online, or import them into your library when you want a local copy."
        }

        return "Browse remote folders directly, jump back into a comic you were reading, or import folders into your local library without leaving this tab."
    }

    var continueReadingSession: RemoteComicReadingSession? {
        sessions.first
    }

    var continueReadingProfile: RemoteServerProfile? {
        guard let session = continueReadingSession else {
            return nil
        }

        return profile(for: session.serverID)
    }

    var serverCountText: String {
        "\(profiles.count)"
    }

    var shortcutCountText: String {
        "\(shortcutEntries.count)"
    }

    var sessionCountText: String {
        "\(sessions.count)"
    }

    var cacheSummaryText: String {
        cacheSummary.isEmpty ? "No downloaded remote comics" : cacheSummary.summaryText
    }

    var offlineReadySessions: [RemoteComicReadingSession] {
        offlineEntries.map(\.session)
    }

    var offlineShelfPreviewSessions: [RemoteComicReadingSession] {
        guard let continueReadingSession else {
            return offlineReadySessions
        }

        return offlineReadySessions.filter { $0.id != continueReadingSession.id }
    }

    var offlineReadyCountText: String {
        "\(offlineReadySessions.count)"
    }

    var thumbnailCacheSummaryText: String {
        thumbnailCacheSummary.isEmpty ? "No saved thumbnails yet" : thumbnailCacheSummary.summaryText
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func refreshIfLoaded() async {
        guard hasLoaded else {
            return
        }

        await load()
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let offlineSnapshot = try remoteOfflineLibrarySnapshotStore.loadSnapshot()
            profiles = offlineSnapshot.profiles
            shortcutEntries = try remoteFolderShortcutSnapshotStore.loadEntries()
            sessions = offlineSnapshot.sessions
            offlineEntries = offlineSnapshot.offlineEntries
            cacheSummary = offlineSnapshot.cacheSummary
            thumbnailCacheSummary = RemoteComicThumbnailPipeline.shared.cacheSummary()
            alert = nil
        } catch {
            profiles = []
            shortcutEntries = []
            sessions = []
            offlineEntries = []
            cacheSummary = .empty
            thumbnailCacheSummary = .empty
            alert = BrowseHomeAlert(
                title: "Browse Not Ready",
                message: error.localizedDescription
            )
        }
    }

    func profile(for serverID: UUID) -> RemoteServerProfile? {
        profiles.first { $0.id == serverID }
    }
}

struct BrowseHomeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
