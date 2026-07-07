import Foundation
import Network
import os

/// Manages a pool of reusable SMB connections keyed by server profile ID.
/// Connections are kept alive with an idle timeout and shared across operations.
actor SMBConnectionPool {
    struct PoolKey: Hashable {
        let host: String
        let port: Int
        let shareName: String
        let username: String?
    }

    private struct PooledConnection {
        let id: ObjectIdentifier
        let client: SMBClient
        let key: PoolKey
        var lastUsedAt: Date
        var isInUse: Bool
    }

    private var connections: [PoolKey: [PooledConnection]] = [:]
    private let idleTimeout: TimeInterval = 60
    private let connectTimeout: TimeInterval = 15
    private var cleanupTask: Task<Void, Never>?
    private let logger = AppLog.smb

    deinit {
        cleanupTask?.cancel()
    }

    /// Execute an operation with a pooled SMB connection.
    /// Reuses existing connections when possible, creates new ones when needed.
    func withConnection<T>(
        host: String,
        port: Int,
        shareName: String,
        username: String?,
        password: String?,
        operation: (SMBClient) async throws -> T
    ) async throws -> T {
        let key = PoolKey(
            host: host,
            port: port,
            shareName: shareName,
            username: normalizedUsername(username)
        )

        let client = try await acquireConnection(
            key: key,
            username: username,
            password: password
        )

        do {
            let result = try await operation(client)
            releaseConnection(client, for: key)
            return result
        } catch {
            let shouldEvict = shouldEvictConnection(for: error)
            if shouldEvict {
                logger.warning(
                    "SMB pooled connection operation failed endpointID=\(self.endpointLogID(for: key), privacy: .public) action=evict error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
                evictConnection(client, for: key)
            } else {
                releaseConnection(client, for: key)
            }
            throw error
        }
    }

    /// Close all pooled connections immediately.
    func closeAll() {
        let connectionCount = connections.values.reduce(0) { $0 + $1.count }
        if connectionCount > 0 {
            logger.notice(
                "SMB connection pool close all requested connections=\(connectionCount)"
            )
        }

        let clients = connections.values.flatMap { entries in
            entries.map(\.client)
        }
        connections.removeAll()
        clients.forEach { disconnect($0) }
    }

    /// Evict connections for a specific server.
    func evictConnections(host: String, port: Int) {
        let keysToRemove = connections.keys.filter { $0.host == host && $0.port == port }
        let connectionCount = keysToRemove.reduce(0) { count, key in
            count + (connections[key]?.count ?? 0)
        }
        if connectionCount > 0 {
            logger.notice(
                "SMB connection pool server eviction requested serverID=\(self.serverLogID(host: host, port: port), privacy: .public) groups=\(keysToRemove.count) connections=\(connectionCount)"
            )
        }

        let clients = keysToRemove.flatMap { key in
            connections[key]?.map(\.client) ?? []
        }
        for key in keysToRemove {
            connections.removeValue(forKey: key)
        }
        clients.forEach { disconnect($0) }
    }

    // MARK: - Private

    private func acquireConnection(
        key: PoolKey,
        username: String?,
        password: String?
    ) async throws -> SMBClient {
        if var entries = connections[key],
           let idleIndex = entries.firstIndex(where: { !$0.isInUse }) {
            entries[idleIndex].isInUse = true
            entries[idleIndex].lastUsedAt = Date()
            let client = entries[idleIndex].client
            connections[key] = entries
            logger.debug(
                "SMB pooled connection reused endpointID=\(self.endpointLogID(for: key), privacy: .public) pooled=\(entries.count)"
            )
            return client
        }

        // Create new connection
        let client = SMBClient(host: key.host, port: key.port, connectTimeout: connectTimeout)
        logger.info(
            "SMB pooled connection create requested endpointID=\(self.endpointLogID(for: key), privacy: .public)"
        )

        client.onDisconnected = { [weak self, weak client] _ in
            guard let client else {
                return
            }

            Task { [weak self] in
                await self?.handleUnexpectedDisconnect(client, for: key)
            }
        }

        do {
            try await client.login(username: username, password: password)
            try await client.connectShare(key.shareName)
        } catch {
            logger.error(
                "SMB pooled connection create failed endpointID=\(self.endpointLogID(for: key), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            disconnect(client)
            throw error
        }

        let entry = PooledConnection(
            id: ObjectIdentifier(client),
            client: client,
            key: key,
            lastUsedAt: Date(),
            isInUse: true
        )
        connections[key, default: []].append(entry)
        logger.info(
            "SMB pooled connection create completed endpointID=\(self.endpointLogID(for: key), privacy: .public) pooled=\(self.connections[key]?.count ?? 0)"
        )

        scheduleCleanupIfNeeded()
        return client
    }

    private func releaseConnection(_ client: SMBClient, for key: PoolKey) {
        guard var entries = connections[key] else { return }
        let clientID = ObjectIdentifier(client)
        guard let index = entries.firstIndex(where: { $0.id == clientID }) else { return }
        entries[index].isInUse = false
        entries[index].lastUsedAt = Date()
        connections[key] = entries
    }

    private func evictConnection(_ client: SMBClient, for key: PoolKey) {
        guard var entries = connections[key] else { return }
        let clientID = ObjectIdentifier(client)
        guard let index = entries.firstIndex(where: { $0.id == clientID }) else { return }

        let entry = entries.remove(at: index)
        if entries.isEmpty {
            connections.removeValue(forKey: key)
        } else {
            connections[key] = entries
        }
        disconnect(entry.client)
    }

    private func handleUnexpectedDisconnect(_ client: SMBClient, for key: PoolKey) {
        guard containsConnection(client, for: key) else {
            return
        }

        logger.warning(
            "SMB pooled connection disconnected endpointID=\(self.endpointLogID(for: key), privacy: .public) action=evict"
        )
        evictConnection(client, for: key)
    }

    private func scheduleCleanupIfNeeded() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                await self?.cleanupIdleConnections()
                if await self?.connections.isEmpty == true {
                    await self?.clearCleanupTask()
                    break
                }
            }
        }
    }

    private func clearCleanupTask() {
        cleanupTask = nil
    }

    private func cleanupIdleConnections() {
        let now = Date()
        for key in Array(connections.keys) {
            guard var entries = connections[key] else {
                continue
            }

            let expiredEntries = entries.filter {
                !$0.isInUse && now.timeIntervalSince($0.lastUsedAt) > idleTimeout
            }
            entries.removeAll {
                !$0.isInUse && now.timeIntervalSince($0.lastUsedAt) > idleTimeout
            }

            if entries.isEmpty {
                connections.removeValue(forKey: key)
            } else {
                connections[key] = entries
            }

            expiredEntries.forEach { disconnect($0.client) }
            if !expiredEntries.isEmpty {
                logger.info(
                    "SMB connection pool idle cleanup completed endpointID=\(self.endpointLogID(for: key), privacy: .public) expired=\(expiredEntries.count) remaining=\(entries.count)"
                )
            }
        }
    }

    private func shouldEvictConnection(for error: Error) -> Bool {
        error is ConnectionError || error is NWError || error is POSIXError
    }

    private func containsConnection(_ client: SMBClient, for key: PoolKey) -> Bool {
        let clientID = ObjectIdentifier(client)
        return connections[key]?.contains(where: { $0.id == clientID }) == true
    }

    private func normalizedUsername(_ username: String?) -> String? {
        guard let username else {
            return nil
        }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func disconnect(_ client: SMBClient) {
        Task { @MainActor in
            client.session.disconnect()
        }
    }

    private func endpointLogID(for key: PoolKey) -> String {
        AppLogSanitizer.hashedIdentifier(
            [
                key.host.lowercased(),
                String(key.port),
                key.shareName.lowercased(),
                key.username?.lowercased() ?? "<anonymous>"
            ].joined(separator: "|")
        )
    }

    private func serverLogID(host: String, port: Int) -> String {
        AppLogSanitizer.hashedIdentifier("\(host.lowercased())|\(port)")
    }
}
