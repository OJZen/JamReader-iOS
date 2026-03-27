import Foundation

/// Manages a pool of reusable SMB connections keyed by server profile ID.
/// Connections are kept alive with an idle timeout and shared across operations.
actor SMBConnectionPool {
    struct PoolKey: Hashable {
        let host: String
        let port: Int
        let shareName: String
    }

    private struct PooledConnection {
        let client: SMBClient
        let key: PoolKey
        var lastUsedAt: Date
        var activeOperations: Int
    }

    private var connections: [PoolKey: PooledConnection] = [:]
    private let idleTimeout: TimeInterval = 60
    private let connectTimeout: TimeInterval = 15
    private var cleanupTask: Task<Void, Never>?

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
        let key = PoolKey(host: host, port: port, shareName: shareName)

        let client = try await acquireConnection(
            key: key,
            username: username,
            password: password
        )

        do {
            let result = try await operation(client)
            markOperationComplete(key: key)
            return result
        } catch {
            // On error, evict the connection (it may be broken)
            evictConnection(key: key)
            throw error
        }
    }

    /// Close all pooled connections immediately.
    func closeAll() {
        for entry in connections.values {
            entry.client.session.disconnect()
        }
        connections.removeAll()
    }

    /// Evict connections for a specific server.
    func evictConnections(host: String, port: Int) {
        let keysToRemove = connections.keys.filter { $0.host == host && $0.port == port }
        for key in keysToRemove {
            connections[key]?.client.session.disconnect()
            connections.removeValue(forKey: key)
        }
    }

    // MARK: - Private

    private func acquireConnection(
        key: PoolKey,
        username: String?,
        password: String?
    ) async throws -> SMBClient {
        // Try reusing existing connection
        if var entry = connections[key] {
            entry.activeOperations += 1
            entry.lastUsedAt = Date()
            connections[key] = entry
            return entry.client
        }

        // Create new connection
        let client = SMBClient(host: key.host, port: key.port, connectTimeout: connectTimeout)

        client.onDisconnected = { [weak self] _ in
            Task { [weak self] in
                await self?.evictConnection(key: key)
            }
        }

        try await client.login(username: username, password: password)
        try await client.connectShare(key.shareName)

        connections[key] = PooledConnection(
            client: client,
            key: key,
            lastUsedAt: Date(),
            activeOperations: 1
        )

        scheduleCleanupIfNeeded()
        return client
    }

    private func markOperationComplete(key: PoolKey) {
        guard var entry = connections[key] else { return }
        entry.activeOperations = max(entry.activeOperations - 1, 0)
        entry.lastUsedAt = Date()
        connections[key] = entry
    }

    private func evictConnection(key: PoolKey) {
        if let entry = connections.removeValue(forKey: key) {
            entry.client.session.disconnect()
        }
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
        let expiredKeys = connections.filter { _, entry in
            entry.activeOperations == 0 && now.timeIntervalSince(entry.lastUsedAt) > idleTimeout
        }.map(\.key)

        for key in expiredKeys {
            evictConnection(key: key)
        }
    }
}
