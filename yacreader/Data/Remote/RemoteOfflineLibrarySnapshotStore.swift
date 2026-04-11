import Foundation

struct RemoteOfflineComicEntry: Identifiable, Hashable {
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability

    var id: String {
        session.id
    }
}

struct RemoteOfflineLibrarySnapshot {
    let profiles: [RemoteServerProfile]
    let sessions: [RemoteComicReadingSession]
    let offlineEntries: [RemoteOfflineComicEntry]
    let cacheSummary: RemoteComicCacheSummary
}

final class RemoteOfflineLibrarySnapshotStore {
    private let remoteServerProfileStore: RemoteServerProfileStore
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private var cachedSnapshot: RemoteOfflineLibrarySnapshot?

    init(
        remoteServerProfileStore: RemoteServerProfileStore,
        remoteReadingProgressStore: RemoteReadingProgressStore,
        remoteServerBrowsingService: RemoteServerBrowsingService
    ) {
        self.remoteServerProfileStore = remoteServerProfileStore
        self.remoteReadingProgressStore = remoteReadingProgressStore
        self.remoteServerBrowsingService = remoteServerBrowsingService
    }

    func loadSnapshot(forceRefresh: Bool = false) throws -> RemoteOfflineLibrarySnapshot {
        if !forceRefresh, let cachedSnapshot {
            return cachedSnapshot
        }

        let profiles = try remoteServerProfileStore.load()
        let sessions = try remoteReadingProgressStore.loadSessions()
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        let offlineEntries: [RemoteOfflineComicEntry] = sessions.compactMap { session -> RemoteOfflineComicEntry? in
            guard let profile = profilesByID[session.serverID],
                  session.matches(profile: profile) else {
                return nil
            }

            let availability = remoteServerBrowsingService.cachedAvailability(
                for: session.resolvedComicFileReference(for: profile)
            )
            guard availability.hasLocalCopy else {
                return nil
            }

            return RemoteOfflineComicEntry(
                session: session,
                profile: profile,
                availability: availability
            )
        }

        let snapshot = RemoteOfflineLibrarySnapshot(
            profiles: profiles,
            sessions: sessions,
            offlineEntries: offlineEntries,
            cacheSummary: remoteServerBrowsingService.cacheSummary()
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    func invalidate() {
        cachedSnapshot = nil
    }
}
