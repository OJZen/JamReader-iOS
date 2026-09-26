import Foundation
import Network
import os

@MainActor
final class ManagedSMBRemoteFileReader: RemoteRandomAccessFileReader, @unchecked Sendable {
    struct Resources: @unchecked Sendable {
        let client: SMBClient
        let fileReader: FileReader
    }

    private var resources: Resources?
    private let reconnect: @MainActor () async throws -> Resources
    private var reconnectTask: Task<Void, Error>?
    private var expectedFileSize: UInt64?

    init(resources: Resources, reconnect: @escaping @MainActor () async throws -> Resources) {
        self.resources = resources
        self.reconnect = reconnect
    }

    var fileSize: UInt64 {
        get async throws {
            let size = try await withFileReader { try await $0.fileSize }
            expectedFileSize = size
            return size
        }
    }

    func read(offset: UInt64, length: UInt32) async throws -> Data {
        try await withFileReader { try await $0.read(offset: offset, length: length) }
    }

    func close() async throws {
        reconnectTask?.cancel()
        reconnectTask = nil
        let resources = self.resources
        self.resources = nil
        guard let resources else {
            return
        }

        await Self.closeResources(resources, context: "explicitClose")
    }

    deinit {
        reconnectTask?.cancel()
        guard let resources else {
            return
        }

        Task {
            await Self.closeResources(resources, context: "deinit")
        }
    }

    private func withFileReader<T>(_ operation: (FileReader) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let fileReader = try currentFileReader()
        do {
            let result = try await operation(fileReader)
            try Task.checkCancellation()
            _ = try currentFileReader()
            return result
        } catch {
            try Task.checkCancellation()
            guard Self.shouldReconnect(after: error) else { throw error }
            try await recoverConnection(after: fileReader)
            let result = try await operation(currentFileReader())
            try Task.checkCancellation()
            _ = try currentFileReader()
            return result
        }
    }

    private func recoverConnection(after failedReader: FileReader) async throws {
        // Another page may already have replaced the connection that failed this read.
        guard try currentFileReader() === failedReader else { return }
        if reconnectTask == nil {
            resources?.client.session.disconnect()
            let reconnect = self.reconnect
            let expectedFileSize = self.expectedFileSize
            reconnectTask = Task { @MainActor [weak self] in
                AppLog.smb.notice("SMB streaming reader reconnect requested")
                do {
                    let replacement = try await reconnect()
                    do {
                        try Task.checkCancellation()
                        if let expectedFileSize,
                           try await replacement.fileReader.fileSize != expectedFileSize {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        try Task.checkCancellation()
                        guard let self, self.resources != nil else { throw CancellationError() }
                        self.resources = replacement
                        self.reconnectTask = nil
                        AppLog.smb.info("SMB streaming reader reconnect completed")
                    } catch {
                        // Closing the reader while login is suspended must not revive it.
                        replacement.client.session.disconnect()
                        await Self.closeResources(replacement, context: "discardedReconnect")
                        throw error
                    }
                } catch {
                    self?.reconnectTask = nil
                    if !Task.isCancelled {
                        AppLog.smb.warning(
                            "SMB streaming reader reconnect failed error=\(AppLogSanitizer.errorDescription(error), privacy: .private)"
                        )
                    }
                    throw error
                }
            }
        }
        try await reconnectTask?.value
        try Task.checkCancellation()
        _ = try currentFileReader()
    }

    private static func shouldReconnect(after error: Error) -> Bool {
        if error is CancellationError { return false }
        if error is ConnectionError || error is NWError || error is POSIXError { return true }
        if let response = error as? ErrorResponse {
            switch NTStatus(response.header.status) {
            case .userSessionDeleted, .networkSessionExpired, .networkNameDeleted,
                 .fileClosed, .smbBadTid, .smbBadUID, .ioTimeout, .connectionRefused:
                return true
            default:
                return false
            }
        }
        return false
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
        guard let resources else {
            throw CancellationError()
        }

        return resources.fileReader
    }
}
