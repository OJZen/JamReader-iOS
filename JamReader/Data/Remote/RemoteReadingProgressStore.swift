import Foundation
import os

final class RemoteReadingProgressStore {
    private let storage: FileBackedJSONStore
    private let maximumStoredSessions: Int
    private let logger = AppLog.reader
    private var cachedSessions: [RemoteComicReadingSession]?

    init(
        fileManager: FileManager = .default,
        maximumStoredSessions: Int = 200
    ) {
        self.storage = FileBackedJSONStore(fileName: "remote_reading_progress.json", fileManager: fileManager)
        self.maximumStoredSessions = maximumStoredSessions
    }

    init(
        storage: FileBackedJSONStore,
        maximumStoredSessions: Int = 200
    ) {
        self.storage = storage
        self.maximumStoredSessions = maximumStoredSessions
    }

    func loadSessions() throws -> [RemoteComicReadingSession] {
        if let cachedSessions {
            return cachedSessions
        }

        let sessions = try storage.load([RemoteComicReadingSession].self) ?? []
        let sortedSessions = sessions.sorted { lhs, rhs in
            lhs.lastTimeOpened > rhs.lastTimeOpened
        }
        cachedSessions = sortedSessions
        return sortedSessions
    }

    func loadProgress(
        for reference: RemoteComicFileReference
    ) throws -> RemoteComicReadingSession? {
        try loadSessions().first { $0.matches(reference: reference) }
    }

    func mostRecentSession() throws -> RemoteComicReadingSession? {
        try loadSessions().first
    }

    func latestSessionsByServerID() throws -> [UUID: RemoteComicReadingSession] {
        try loadSessions().reduce(into: [:]) { result, session in
            if result[session.serverID] == nil {
                result[session.serverID] = session
            }
        }
    }

    func saveProgress(
        _ progress: ComicReadingProgress,
        for reference: RemoteComicFileReference,
        profile: RemoteServerProfile,
        bookmarkPageIndices: [Int] = []
    ) throws {
        var sessions = try loadSessions()
        let updatedSession = RemoteComicReadingSession(
            serverID: reference.serverID,
            providerKind: reference.providerKind,
            serverName: profile.name,
            shareName: reference.shareName,
            cacheScopeKey: reference.cacheScopeKey ?? profile.remoteCacheScopeKey,
            path: reference.path,
            fileName: reference.fileName,
            contentKind: reference.contentKind,
            pageCount: progress.pageCount,
            currentPage: progress.currentPage,
            hasBeenOpened: progress.hasBeenOpened,
            read: progress.read,
            lastTimeOpened: progress.lastTimeOpened,
            fileSize: reference.fileSize,
            modifiedAt: reference.modifiedAt,
            bookmarkPageIndices: bookmarkPageIndices
        )

        sessions.removeAll { $0.matches(reference: reference) }
        sessions.append(updatedSession)
        sessions.sort { lhs, rhs in
            lhs.lastTimeOpened > rhs.lastTimeOpened
        }

        if sessions.count > maximumStoredSessions {
            let discardedCount = sessions.count - maximumStoredSessions
            sessions = Array(sessions.prefix(maximumStoredSessions))
            logger.info(
                "Remote reading history trimmed discarded=\(discardedCount, privacy: .public) retained=\(sessions.count, privacy: .public) maximum=\(self.maximumStoredSessions, privacy: .public)"
            )
        }

        try saveSessions(sessions)
    }

    func deleteSessions(for serverID: UUID) throws {
        let sessions = try loadSessions()
        let filteredSessions = sessions.filter { $0.serverID != serverID }
        try saveSessions(filteredSessions)
        logger.info(
            "Remote reading history deleted scope=server serverID=\(serverID.uuidString, privacy: .public) removed=\(sessions.count - filteredSessions.count, privacy: .public) remaining=\(filteredSessions.count, privacy: .public)"
        )
    }

    func deleteSessions(for profile: RemoteServerProfile) throws {
        let sessions = try loadSessions()
        let filteredSessions = sessions.filter { !$0.matches(profile: profile) }
        try saveSessions(filteredSessions)
        logger.info(
            "Remote reading history deleted scope=profile provider=\(profile.providerKind.rawValue, privacy: .public) serverID=\(profile.id.uuidString, privacy: .public) removed=\(sessions.count - filteredSessions.count, privacy: .public) remaining=\(filteredSessions.count, privacy: .public)"
        )
    }

    func deleteSession(_ session: RemoteComicReadingSession) throws {
        let sessions = try loadSessions()
        let filteredSessions = sessions.filter { candidate in
            candidate.id != session.id
        }
        try saveSessions(filteredSessions)
        logger.info(
            "Remote reading history deleted scope=session serverID=\(session.serverID.uuidString, privacy: .public) removed=\(sessions.count - filteredSessions.count, privacy: .public) remaining=\(filteredSessions.count, privacy: .public)"
        )
    }

    func clearAllSessions() throws {
        let sessions = try loadSessions()
        try saveSessions([])
        logger.notice(
            "Remote reading history cleared removed=\(sessions.count, privacy: .public)"
        )
    }

    private func saveSessions(_ sessions: [RemoteComicReadingSession]) throws {
        try storage.save(sessions)
        cachedSessions = sessions
    }
}
