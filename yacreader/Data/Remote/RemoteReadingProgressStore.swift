import Foundation

final class RemoteReadingProgressStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maximumStoredSessions: Int

    init(
        fileManager: FileManager = .default,
        maximumStoredSessions: Int = 200
    ) {
        self.fileManager = fileManager
        self.maximumStoredSessions = maximumStoredSessions

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSessions() throws -> [RemoteComicReadingSession] {
        let storageURL = try storageFileURL()
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        let sessions = try decoder.decode([RemoteComicReadingSession].self, from: data)
        return sessions.sorted { lhs, rhs in
            lhs.lastTimeOpened > rhs.lastTimeOpened
        }
    }

    func loadProgress(
        for reference: RemoteComicFileReference
    ) throws -> RemoteComicReadingSession? {
        try loadSessions().first { session in
            session.serverID == reference.serverID && session.path == reference.path
        }
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

        sessions.removeAll { session in
            session.serverID == reference.serverID && session.path == reference.path
        }
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

    private func saveSessions(_ sessions: [RemoteComicReadingSession]) throws {
        let storageURL = try storageFileURL()
        let data = try encoder.encode(sessions)
        try data.write(to: storageURL, options: .atomic)
    }

    private func storageFileURL() throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("YACReader", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("remote_reading_progress.json")
    }
}
