import Foundation
import os

struct RemoteOfflineCopyRecord: Codable, Hashable, Identifiable {
    let serverID: UUID
    let providerKind: RemoteProviderKind
    let shareName: String
    let cacheScopeKey: String?
    let path: String
    let fileName: String
    let fileSize: Int64?
    let modifiedAt: Date?
    let contentKind: RemoteComicReferenceKind
    let pageCountHint: Int?
    let coverPath: String?
    let savedAt: Date

    init(
        reference: RemoteComicFileReference,
        savedAt: Date = Date()
    ) {
        self.serverID = reference.serverID
        self.providerKind = reference.providerKind
        self.shareName = reference.shareName
        self.cacheScopeKey = reference.cacheScopeKey
        self.path = reference.path
        self.fileName = reference.fileName
        self.fileSize = reference.fileSize
        self.modifiedAt = reference.modifiedAt
        self.contentKind = reference.contentKind
        self.pageCountHint = reference.pageCountHint
        self.coverPath = reference.coverPath
        self.savedAt = savedAt
    }

    var id: String {
        reference.id
    }

    var reference: RemoteComicFileReference {
        RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            contentKind: contentKind,
            pageCountHint: pageCountHint,
            coverPath: coverPath
        )
    }

    func matches(profile: RemoteServerProfile) -> Bool {
        guard serverID == profile.id,
              profile.matchesRemoteScope(
                  providerKind: providerKind,
                  providerRootIdentifier: shareName
              ) else {
            return false
        }

        if let cacheScopeKey {
            return cacheScopeKey == profile.remoteCacheScopeKey
        }

        return true
    }

    func resolvedReference(for profile: RemoteServerProfile) -> RemoteComicFileReference {
        guard cacheScopeKey == nil, matches(profile: profile) else {
            return reference
        }

        return RemoteComicFileReference(
            serverID: serverID,
            providerKind: providerKind,
            shareName: shareName,
            cacheScopeKey: profile.remoteCacheScopeKey,
            path: path,
            fileName: fileName,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            contentKind: contentKind,
            pageCountHint: pageCountHint,
            coverPath: coverPath
        )
    }

    func placeholderReadingSession(for profile: RemoteServerProfile) -> RemoteComicReadingSession {
        RemoteComicReadingSession(
            serverID: serverID,
            providerKind: providerKind,
            serverName: profile.name,
            shareName: shareName,
            cacheScopeKey: cacheScopeKey ?? profile.remoteCacheScopeKey,
            path: path,
            fileName: fileName,
            contentKind: contentKind,
            pageCount: pageCountHint,
            currentPage: 0,
            hasBeenOpened: false,
            read: false,
            lastTimeOpened: savedAt,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }
}

struct RemoteOfflineCopyPersistenceCandidate {
    let reference: RemoteComicFileReference
    let result: RemoteComicDownloadResult
}

enum RemoteOfflineCopyPersistenceCoordinator {
    static func persist(
        candidates: [RemoteOfflineCopyPersistenceCandidate],
        persistRecords: () throws -> Void,
        commitDownloadedCache: (RemoteOfflineCopyPersistenceCandidate) throws -> Void,
        rollbackDownloadedCache: (RemoteOfflineCopyPersistenceCandidate) throws -> Void,
        commitFailureHandler: (RemoteComicFileReference, Error) -> Void = { _, _ in },
        rollbackFailureHandler: (RemoteComicFileReference, Error) -> Void = { _, _ in }
    ) throws {
        do {
            try persistRecords()
        } catch {
            let persistenceError = error
            for candidate in candidates where candidate.result.cacheMutation.requiresFinalization {
                do {
                    try rollbackDownloadedCache(candidate)
                } catch {
                    rollbackFailureHandler(candidate.reference, error)
                }
            }
            throw persistenceError
        }

        for candidate in candidates where candidate.result.cacheMutation.requiresFinalization {
            do {
                try commitDownloadedCache(candidate)
            } catch {
                commitFailureHandler(candidate.reference, error)
            }
        }
    }
}

final class RemoteOfflineCopyStore {
    private struct StorageEnvelope: Codable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int
        var completedCacheRecoveryMigration: Bool
        var records: [RemoteOfflineCopyRecord]

        static let empty = StorageEnvelope(
            schemaVersion: currentSchemaVersion,
            completedCacheRecoveryMigration: false,
            records: []
        )
    }

    private let storage: FileBackedJSONStore
    private let lock = NSLock()
    private let logger = AppLog.remoteCache
    private var cachedEnvelope: StorageEnvelope?

    init(fileManager: FileManager = .default) {
        self.storage = FileBackedJSONStore(
            fileName: "remote_offline_copies.json",
            fileManager: fileManager
        )
    }

    init(storage: FileBackedJSONStore) {
        self.storage = storage
    }

    func loadRecords(
        recoveringExistingCache makeRecoveredRecords: () throws -> [RemoteOfflineCopyRecord]
    ) throws -> [RemoteOfflineCopyRecord] {
        lock.lock()
        defer { lock.unlock() }

        var envelope = try loadEnvelopeLocked()
        if !envelope.completedCacheRecoveryMigration {
            let recoveredRecords = try makeRecoveredRecords()
            envelope.records = Self.mergedRecords(
                existing: envelope.records,
                additions: recoveredRecords
            )
            envelope.completedCacheRecoveryMigration = true
            try saveEnvelopeLocked(envelope)
            logger.info(
                "Remote offline copy cache recovery completed recovered=\(recoveredRecords.count, privacy: .public) total=\(envelope.records.count, privacy: .public)"
            )
        }

        return Self.sortedRecords(envelope.records)
    }

    func loadRecords() throws -> [RemoteOfflineCopyRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sortedRecords(try loadEnvelopeLocked().records)
    }

    func recordDownloadedCopy(
        for reference: RemoteComicFileReference,
        savedAt: Date = Date()
    ) throws {
        try recordDownloadedCopies(for: [reference], savedAt: savedAt)
    }

    func recordDownloadedCopies(
        for references: [RemoteComicFileReference],
        savedAt: Date = Date()
    ) throws {
        guard !references.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        var envelope = try loadEnvelopeLocked()
        let additions = references.map {
            RemoteOfflineCopyRecord(reference: $0, savedAt: savedAt)
        }
        envelope.records = Self.mergedRecords(
            existing: envelope.records,
            additions: additions
        )
        try saveEnvelopeLocked(envelope)
        logger.info(
            "Remote offline copies recorded additions=\(additions.count, privacy: .public) total=\(envelope.records.count, privacy: .public)"
        )
    }

    func removeCopy(for reference: RemoteComicFileReference) throws {
        try removeCopies(for: [reference])
    }

    func removeCopies(for references: [RemoteComicFileReference]) throws {
        guard !references.isEmpty else {
            return
        }

        let referenceIDs = Set(references.map(\.id))
        try removeRecords { record in
            referenceIDs.contains(record.id)
                || references.contains { record.reference.matchesCacheIdentity(of: $0) }
        }
    }

    func removeCopies(for profile: RemoteServerProfile) throws {
        try removeRecords { $0.matches(profile: profile) }
    }

    func removeCopies(forServerID serverID: UUID) throws {
        try removeRecords { $0.serverID == serverID }
    }

    func removeCopies(
        matching invalidRecords: Set<RemoteOfflineCopyRecord>,
        ifStillInvalid: (RemoteOfflineCopyRecord) -> Bool
    ) throws {
        guard !invalidRecords.isEmpty else {
            return
        }

        try removeRecords { record in
            invalidRecords.contains(record) && ifStillInvalid(record)
        }
    }

    func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }

        var envelope = try loadEnvelopeLocked()
        let removedCount = envelope.records.count
        envelope.records = []
        envelope.completedCacheRecoveryMigration = true
        try saveEnvelopeLocked(envelope)
        logger.notice(
            "Remote offline copy records cleared removed=\(removedCount, privacy: .public)"
        )
    }

    private func removeRecords(
        matching shouldRemove: (RemoteOfflineCopyRecord) -> Bool
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var envelope = try loadEnvelopeLocked()
        let previousCount = envelope.records.count
        envelope.records.removeAll(where: shouldRemove)
        guard envelope.records.count != previousCount else {
            return
        }

        try saveEnvelopeLocked(envelope)
        logger.info(
            "Remote offline copy records removed count=\(previousCount - envelope.records.count, privacy: .public) remaining=\(envelope.records.count, privacy: .public)"
        )
    }

    private func loadEnvelopeLocked() throws -> StorageEnvelope {
        if let cachedEnvelope {
            return cachedEnvelope
        }

        do {
            let envelope = try storage.load(StorageEnvelope.self) ?? .empty
            cachedEnvelope = envelope
            return envelope
        } catch is DecodingError {
            let recoveredEnvelope = try recoverCorruptStorageLocked()
            cachedEnvelope = recoveredEnvelope
            return recoveredEnvelope
        }
    }

    private func saveEnvelopeLocked(_ envelope: StorageEnvelope) throws {
        var normalizedEnvelope = envelope
        normalizedEnvelope.schemaVersion = StorageEnvelope.currentSchemaVersion
        normalizedEnvelope.records = Self.sortedRecords(envelope.records)
        try storage.save(normalizedEnvelope)
        cachedEnvelope = normalizedEnvelope
    }

    private func recoverCorruptStorageLocked() throws -> StorageEnvelope {
        let storageURL = try storage.storageFileURL()
        if storage.fileManager.fileExists(atPath: storageURL.path) {
            let recoveryURL = storageURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(UUID().uuidString).json")
            try storage.fileManager.moveItem(at: storageURL, to: recoveryURL)
            logger.error(
                "Remote offline copy records recovered from invalid JSON backup=\(AppLogSanitizer.truncated(recoveryURL.lastPathComponent), privacy: .public)"
            )
        }

        let envelope = StorageEnvelope.empty
        try storage.save(envelope)
        return envelope
    }

    private static func mergedRecords(
        existing: [RemoteOfflineCopyRecord],
        additions: [RemoteOfflineCopyRecord]
    ) -> [RemoteOfflineCopyRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for record in additions {
            recordsByID[record.id] = record
        }
        return sortedRecords(Array(recordsByID.values))
    }

    private static func sortedRecords(
        _ records: [RemoteOfflineCopyRecord]
    ) -> [RemoteOfflineCopyRecord] {
        records.sorted { lhs, rhs in
            if lhs.savedAt == rhs.savedAt {
                return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }
            return lhs.savedAt > rhs.savedAt
        }
    }
}

private extension RemoteComicFileReference {
    func matchesCacheIdentity(of other: RemoteComicFileReference) -> Bool {
        serverID == other.serverID
            && providerKind == other.providerKind
            && shareName == other.shareName
            && contentKind == other.contentKind
            && path == other.path
    }
}
