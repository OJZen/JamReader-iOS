import Foundation
import os

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
    private let logger = AppLog.remoteCache
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

        var missingProfileCount = 0
        var profileMismatchCount = 0
        var missingLocalCopyCount = 0
        let offlineEntries: [RemoteOfflineComicEntry] = sessions.compactMap { session -> RemoteOfflineComicEntry? in
            guard let profile = profilesByID[session.serverID] else {
                missingProfileCount += 1
                return nil
            }

            guard session.matches(profile: profile) else {
                profileMismatchCount += 1
                return nil
            }

            let availability = remoteServerBrowsingService.cachedAvailability(
                for: session.resolvedComicFileReference(for: profile)
            )
            guard availability.hasLocalCopy else {
                missingLocalCopyCount += 1
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
        logSnapshotBuild(
            snapshot,
            forceRefresh: forceRefresh,
            missingProfileCount: missingProfileCount,
            profileMismatchCount: profileMismatchCount,
            missingLocalCopyCount: missingLocalCopyCount
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    func invalidate() {
        cachedSnapshot = nil
    }

    private func logSnapshotBuild(
        _ snapshot: RemoteOfflineLibrarySnapshot,
        forceRefresh: Bool,
        missingProfileCount: Int,
        profileMismatchCount: Int,
        missingLocalCopyCount: Int
    ) {
        let filteredCount = missingProfileCount + profileMismatchCount + missingLocalCopyCount
        guard forceRefresh || filteredCount > 0 else {
            return
        }

        logger.debug(
            "Remote offline snapshot built forceRefresh=\(forceRefresh, privacy: .public) profiles=\(snapshot.profiles.count, privacy: .public) sessions=\(snapshot.sessions.count, privacy: .public) offline=\(snapshot.offlineEntries.count, privacy: .public) missingProfile=\(missingProfileCount, privacy: .public) profileMismatch=\(profileMismatchCount, privacy: .public) noLocalCopy=\(missingLocalCopyCount, privacy: .public) cacheFiles=\(snapshot.cacheSummary.fileCount, privacy: .public) cacheBytes=\(snapshot.cacheSummary.totalBytes, privacy: .public)"
        )
    }
}
