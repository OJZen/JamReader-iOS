import Foundation
import os

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

        await Self.closeResources(resources, context: "explicitClose")
    }

    deinit {
        let resources = takeResources()
        guard let resources else {
            return
        }

        Task {
            await Self.closeResources(resources, context: "deinit")
        }
    }

    private static func closeResources(_ resources: Resources, context: String) async {
        do {
            try await resources.fileReader.close()
        } catch {
            AppLog.smb.warning(
                "SMB remote file reader cleanup failed context=\(context, privacy: .public) step=fileReaderClose error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            _ = try await resources.client.disconnectShare()
        } catch {
            AppLog.smb.warning(
                "SMB remote file reader cleanup failed context=\(context, privacy: .public) step=disconnectShare error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        do {
            _ = try await resources.client.logoff()
        } catch {
            AppLog.smb.warning(
                "SMB remote file reader cleanup failed context=\(context, privacy: .public) step=logoff error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
        }

        await MainActor.run {
            resources.client.session.disconnect()
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
