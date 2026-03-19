import Combine
import Foundation

@MainActor
final class BrowseHomeViewModel: ObservableObject {
    @Published private(set) var profiles: [RemoteServerProfile] = []
    @Published private(set) var sessions: [RemoteComicReadingSession] = []
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
    @Published private(set) var isLoading = false
    @Published var alert: BrowseHomeAlert?

    private let remoteServerProfileStore: RemoteServerProfileStore
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.remoteServerProfileStore = dependencies.remoteServerProfileStore
        self.remoteReadingProgressStore = dependencies.remoteReadingProgressStore
        self.remoteServerBrowsingService = dependencies.remoteServerBrowsingService
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

    var canShowContinueReading: Bool {
        continueReadingSession != nil && continueReadingProfile != nil
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

    var featuredBrowseProfile: RemoteServerProfile? {
        if let continueReadingProfile {
            return continueReadingProfile
        }

        return profiles.first
    }

    var serverCountText: String {
        "\(profiles.count)"
    }

    var sessionCountText: String {
        "\(sessions.count)"
    }

    var cacheSummaryText: String {
        cacheSummary.isEmpty ? "No downloaded remote comics" : cacheSummary.summaryText
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
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
            profiles = try remoteServerProfileStore.load()
            sessions = try remoteReadingProgressStore.loadSessions()
            cacheSummary = remoteServerBrowsingService.cacheSummary()
            alert = nil
        } catch {
            profiles = []
            sessions = []
            cacheSummary = .empty
            alert = BrowseHomeAlert(
                title: "Browse Not Ready",
                message: error.localizedDescription
            )
        }
    }

    func profile(for serverID: UUID) -> RemoteServerProfile? {
        profiles.first { $0.id == serverID }
    }

    func lastBrowsedPath(for profile: RemoteServerProfile) -> String {
        RemoteServerBrowserViewModel.lastBrowsedPath(for: profile)
    }
}

struct BrowseHomeAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
