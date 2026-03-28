import Foundation

final class ManagedSMBRemoteFileReader: RemoteRandomAccessFileReader, @unchecked Sendable {
    private struct Resources: @unchecked Sendable {
        let client: SMBClient
        let fileReader: FileReader
    }

    private let lock = NSLock()
    private var resources: Resources?

    init(client: SMBClient, fileReader: FileReader) {
        self.resources = Resources(client: client, fileReader: fileReader)
    }

    var fileSize: UInt64 {
        get async throws {
            let fileReader = try currentFileReader()
            return try await fileReader.fileSize
        }
    }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        try Task.checkCancellation()
        let fileReader = try currentFileReader()
        return try await fileReader.read(offset: offset, length: length)
    }

    func close() async throws {
        let resources = takeResources()
        guard let resources else {
            return
        }

        try? await resources.fileReader.close()
        _ = try? await resources.client.disconnectShare()
        _ = try? await resources.client.logoff()
        await MainActor.run {
            resources.client.session.disconnect()
        }
    }

    deinit {
        let resources = takeResources()
        guard let resources else {
            return
        }

        Task {
            try? await resources.fileReader.close()
            _ = try? await resources.client.disconnectShare()
            _ = try? await resources.client.logoff()
            await MainActor.run {
                resources.client.session.disconnect()
            }
        }
    }

    private func currentFileReader() throws -> FileReader {
        lock.lock()
        defer { lock.unlock() }

        guard let resources else {
            throw CancellationError()
        }

        return resources.fileReader
    }

    private func takeResources() -> Resources? {
        lock.lock()
        defer { lock.unlock() }

        let currentResources = resources
        resources = nil
        return currentResources
    }
}
