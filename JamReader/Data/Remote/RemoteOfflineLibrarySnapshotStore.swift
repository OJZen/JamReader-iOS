import Foundation
import os

struct RemoteOfflineComicEntry: Identifiable, Hashable {
    let record: RemoteOfflineCopyRecord
    let session: RemoteComicReadingSession
    let profile: RemoteServerProfile
    let availability: RemoteComicCachedAvailability

    var recordID: String {
        record.id
    }

    var id: String {
        recordID
    }
}

struct RemoteOfflineLibrarySnapshot {
    let profiles: [RemoteServerProfile]
    let sessions: [RemoteComicReadingSession]
    let offlineEntries: [RemoteOfflineComicEntry]
    let cacheSummary: RemoteComicCacheSummary
}

final class RemoteOfflineLibrarySnapshotStore {
    private struct CacheState {
        let snapshot: RemoteOfflineLibrarySnapshot?
        let generation: UInt64
    }

    private let remoteServerProfileStore: RemoteServerProfileStore
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private let remoteOfflineCopyStore: RemoteOfflineCopyStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private let beforeInvalidRecordPruning: ((Set<String>) -> Void)?
    private let logger = AppLog.remoteCache
    private let cacheLock = NSLock()
    private var cachedSnapshot: RemoteOfflineLibrarySnapshot?
    private var cacheGeneration: UInt64 = 0

    init(
        remoteServerProfileStore: RemoteServerProfileStore,
        remoteReadingProgressStore: RemoteReadingProgressStore,
        remoteOfflineCopyStore: RemoteOfflineCopyStore,
        remoteServerBrowsingService: RemoteServerBrowsingService,
        beforeInvalidRecordPruning: ((Set<String>) -> Void)? = nil
    ) {
        self.remoteServerProfileStore = remoteServerProfileStore
        self.remoteReadingProgressStore = remoteReadingProgressStore
        self.remoteOfflineCopyStore = remoteOfflineCopyStore
        self.remoteServerBrowsingService = remoteServerBrowsingService
        self.beforeInvalidRecordPruning = beforeInvalidRecordPruning
    }

    func loadSnapshot(forceRefresh: Bool = false) throws -> RemoteOfflineLibrarySnapshot {
        let initialCacheState = beginLoad(forceRefresh: forceRefresh)
        if !forceRefresh,
           let cachedSnapshot = initialCacheState.snapshot,
           canReuseCachedSnapshot(cachedSnapshot),
           cacheGenerationIsCurrent(initialCacheState.generation) {
            return cachedSnapshot
        }

        let profiles = try remoteServerProfileStore.load()
        let sessions = try remoteReadingProgressStore.loadSessions()
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let sessionsByServerID = Dictionary(grouping: sessions, by: \.serverID)
        let records = try remoteOfflineCopyStore.loadRecords {
            profiles.flatMap { profile in
                remoteServerBrowsingService
                    .recoverableCachedComicCandidates(for: profile)
                    .map { candidate in
                        let matchingSession = sessionsByServerID[profile.id]?.first {
                            $0.matches(reference: candidate.reference)
                        }
                        let reference = matchingSession?
                            .resolvedComicFileReference(for: profile)
                            ?? candidate.reference
                        return RemoteOfflineCopyRecord(
                            reference: reference,
                            savedAt: max(
                                candidate.cachedAt,
                                matchingSession?.lastTimeOpened ?? Date(timeIntervalSince1970: 0)
                            )
                        )
                    }
            }
        }

        var missingProfileCount = 0
        var profileMismatchCount = 0
        var missingLocalCopyCount = 0
        var synthesizedSessionCount = 0
        var invalidRecords: Set<RemoteOfflineCopyRecord> = []
        let offlineEntries: [RemoteOfflineComicEntry] = records.compactMap { record -> RemoteOfflineComicEntry? in
            guard let profile = profilesByID[record.serverID] else {
                missingProfileCount += 1
                invalidRecords.insert(record)
                return nil
            }

            guard record.matches(profile: profile) else {
                profileMismatchCount += 1
                invalidRecords.insert(record)
                return nil
            }

            let reference = record.resolvedReference(for: profile)
            let availability = remoteServerBrowsingService.cachedAvailability(
                for: reference
            )
            guard availability.hasLocalCopy else {
                missingLocalCopyCount += 1
                invalidRecords.insert(record)
                return nil
            }

            let session: RemoteComicReadingSession
            if let storedSession = sessionsByServerID[record.serverID]?.first(where: {
                $0.matches(reference: reference)
            }) {
                session = storedSession
            } else {
                session = record.placeholderReadingSession(for: profile)
                synthesizedSessionCount += 1
            }

            return RemoteOfflineComicEntry(
                record: record,
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
            missingLocalCopyCount: missingLocalCopyCount,
            synthesizedSessionCount: synthesizedSessionCount
        )
        pruneInvalidRecordsIfNeeded(
            invalidRecords: invalidRecords
        )
        cache(snapshot, ifGenerationIsCurrent: initialCacheState.generation)
        return snapshot
    }

    func invalidate() {
        cacheLock.lock()
        cacheGeneration &+= 1
        cachedSnapshot = nil
        cacheLock.unlock()
    }

    private func beginLoad(forceRefresh: Bool) -> CacheState {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if forceRefresh {
            cacheGeneration &+= 1
            cachedSnapshot = nil
        }
        return CacheState(
            snapshot: cachedSnapshot,
            generation: cacheGeneration
        )
    }

    private func cacheGenerationIsCurrent(_ generation: UInt64) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cacheGeneration == generation
    }

    private func cache(
        _ snapshot: RemoteOfflineLibrarySnapshot,
        ifGenerationIsCurrent generation: UInt64
    ) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cacheGeneration == generation else {
            return
        }
        cachedSnapshot = snapshot
    }

    private func canReuseCachedSnapshot(
        _ snapshot: RemoteOfflineLibrarySnapshot
    ) -> Bool {
        guard let profiles = try? remoteServerProfileStore.load(),
              profiles == snapshot.profiles,
              let sessions = try? remoteReadingProgressStore.loadSessions(),
              sessions == snapshot.sessions,
              let records = try? remoteOfflineCopyStore.loadRecords(),
              Set(records) == Set(snapshot.offlineEntries.map(\.record)) else {
            return false
        }

        return snapshot.offlineEntries.allSatisfy { entry in
            remoteServerBrowsingService.cachedAvailability(
                for: entry.session.resolvedComicFileReference(for: entry.profile)
            ).hasLocalCopy
        }
    }

    private func logSnapshotBuild(
        _ snapshot: RemoteOfflineLibrarySnapshot,
        forceRefresh: Bool,
        missingProfileCount: Int,
        profileMismatchCount: Int,
        missingLocalCopyCount: Int,
        synthesizedSessionCount: Int
    ) {
        let filteredCount = missingProfileCount + profileMismatchCount + missingLocalCopyCount
        guard forceRefresh || filteredCount > 0 else {
            return
        }

        logger.debug(
            "Remote offline snapshot built forceRefresh=\(forceRefresh, privacy: .public) profiles=\(snapshot.profiles.count, privacy: .public) sessions=\(snapshot.sessions.count, privacy: .public) offline=\(snapshot.offlineEntries.count, privacy: .public) synthesizedSessions=\(synthesizedSessionCount, privacy: .public) missingProfile=\(missingProfileCount, privacy: .public) profileMismatch=\(profileMismatchCount, privacy: .public) noLocalCopy=\(missingLocalCopyCount, privacy: .public) cacheFiles=\(snapshot.cacheSummary.fileCount, privacy: .public) cacheBytes=\(snapshot.cacheSummary.totalBytes, privacy: .public)"
        )
    }

    private func pruneInvalidRecordsIfNeeded(
        invalidRecords: Set<RemoteOfflineCopyRecord>
    ) {
        guard !invalidRecords.isEmpty else {
            return
        }

        beforeInvalidRecordPruning?(Set(invalidRecords.map(\.id)))
        do {
            let latestProfiles = try remoteServerProfileStore.load()
            let latestProfilesByID = Dictionary(
                uniqueKeysWithValues: latestProfiles.map { ($0.id, $0) }
            )
            try remoteOfflineCopyStore.removeCopies(
                matching: invalidRecords,
                ifStillInvalid: { record in
                    guard let profile = latestProfilesByID[record.serverID],
                          record.matches(profile: profile) else {
                        return true
                    }

                    return !remoteServerBrowsingService.cachedAvailability(
                        for: record.resolvedReference(for: profile)
                    ).hasLocalCopy
                }
            )
        } catch {
            logger.warning(
                "Remote offline copy record pruning failed invalid=\(invalidRecords.count, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }
    }
}
