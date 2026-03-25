import Foundation

final class RemoteReadingProgressStore {
    private let storage: FileBackedJSONStore
    private let maximumStoredSessions: Int
    private var cachedSessions: [RemoteComicReadingSession]?

    init(
        fileManager: FileManager = .default,
        maximumStoredSessions: Int = 200
    ) {
        self.storage = FileBackedJSONStore(fileName: "remote_reading_progress.json", fileManager: fileManager)
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
            path: reference.path,
            fileName: reference.fileName,
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
            sessions = Array(sessions.prefix(maximumStoredSessions))
        }

        try saveSessions(sessions)
    }

    func deleteSessions(for serverID: UUID) throws {
        let filteredSessions = try loadSessions().filter { $0.serverID != serverID }
        try saveSessions(filteredSessions)
    }

    func deleteSessions(for profile: RemoteServerProfile) throws {
        let filteredSessions = try loadSessions().filter { !$0.matches(profile: profile) }
        try saveSessions(filteredSessions)
    }

    func deleteSession(_ session: RemoteComicReadingSession) throws {
        let filteredSessions = try loadSessions().filter { candidate in
            candidate.id != session.id
        }
        try saveSessions(filteredSessions)
    }

    func clearAllSessions() throws {
        try saveSessions([])
    }

    private func saveSessions(_ sessions: [RemoteComicReadingSession]) throws {
        try storage.save(sessions)
        cachedSessions = sessions
    }
}
