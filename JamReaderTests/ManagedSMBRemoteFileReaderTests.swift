import Network
import XCTest
@testable import JamReader

@MainActor
final class ManagedSMBRemoteFileReaderTests: XCTestCase {
    func testExpiredConnectionsRetryTheSameByteRange() async throws {
        let errors: [Error] = [
            ConnectionError.disconnected, ConnectionError.cancelled,
            NWError.posix(.ECONNRESET),
            smbError(.userSessionDeleted), smbError(.networkSessionExpired),
            smbError(.networkNameDeleted), smbError(.fileClosed)
        ]
        for error in errors {
            let stale = resources { _, _ in throw error }
            let fresh = resources { _, _ in Data([1, 2, 3]) }
            var reconnectCount = 0
            let reader = ManagedSMBRemoteFileReader(resources: stale) {
                reconnectCount += 1
                return fresh
            }
            let data = try await reader.read(offset: 123, length: 3)
            XCTAssertEqual(data, Data([1, 2, 3]))
            XCTAssertEqual(reconnectCount, 1)
            XCTAssertEqual(stub(stale).offsets, [123])
            XCTAssertEqual(stub(fresh).offsets, [123])
            XCTAssertEqual(stub(fresh).lengths, [3])
            try await reader.close()
        }
    }

    func testConcurrentAndLateFailuresShareOneReplacement() async throws {
        let reads = [SMBTestGate(), SMBTestGate(), SMBTestGate()]
        let connection = SMBTestGate()
        defer { (reads + [connection]).forEach { $0.open() } }
        let stale = resources { offset, _ in
            await reads[Int(offset)].wait()
            throw ConnectionError.disconnected
        }
        let fresh = resources { offset, _ in Data([UInt8(offset)]) }
        var reconnectCount = 0
        let reader = ManagedSMBRemoteFileReader(resources: stale) {
            reconnectCount += 1
            await connection.wait()
            return fresh
        }
        let tasks = (0..<3).map { index in
            Task { try await reader.read(offset: UInt64(index), length: 1) }
        }
        try await waitUntil { self.stub(stale).offsets.count == 3 }
        reads[0].open()
        reads[1].open()
        try await waitUntil { reconnectCount == 1 }
        connection.open()
        for index in 0..<2 {
            let data = try await tasks[index].value
            XCTAssertEqual(data, Data([UInt8(index)]))
        }
        reads[2].open()
        let lateData = try await tasks[2].value
        XCTAssertEqual(lateData, Data([2]))
        XCTAssertEqual(reconnectCount, 1)
        try await reader.close()
    }

    func testAuthenticationPathAndCancellationErrorsDoNotReconnect() async throws {
        let errors: [Error] = [
            smbError(.logonFailure), smbError(.accessDenied),
            smbError(.objectNameNotFound), CancellationError()
        ]
        for error in errors {
            let stale = resources { _, _ in throw error }
            var reconnectCount = 0
            let reader = ManagedSMBRemoteFileReader(resources: stale) {
                reconnectCount += 1
                return stale
            }
            do {
                _ = try await reader.read(offset: 0, length: 1)
                XCTFail("A permanent or cancelled read must still fail")
            } catch {}
            XCTAssertEqual(reconnectCount, 0)
            try await reader.close()
        }
    }

    func testCancelledPageReadDoesNotReconnectOnALateTransportError() async throws {
        let gate = SMBTestGate()
        defer { gate.open() }
        let stale = resources { _, _ in
            await gate.wait()
            throw ConnectionError.disconnected
        }
        var reconnectCount = 0
        let reader = ManagedSMBRemoteFileReader(resources: stale) {
            reconnectCount += 1
            return stale
        }
        let read = Task { try await reader.read(offset: 0, length: 1) }
        try await waitUntil { self.stub(stale).offsets.count == 1 }
        read.cancel()
        gate.open()
        do {
            _ = try await read.value
            XCTFail("Cancelled page read must not return data")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reconnectCount, 0)
        try await reader.close()
    }

    func testClosingDuringReconnectDiscardsLateConnection() async throws {
        let gate = SMBTestGate()
        defer { gate.open() }
        let stale = resources { _, _ in throw ConnectionError.disconnected }
        let fresh = resources { _, _ in Data([1]) }
        var reconnectCount = 0
        let reader = ManagedSMBRemoteFileReader(resources: stale) {
            reconnectCount += 1
            await gate.wait() // Deliberately ignores cancellation, like a pending SMB login.
            return fresh
        }
        let read = Task { try await reader.read(offset: 0, length: 1) }
        try await waitUntil { reconnectCount == 1 }
        try await reader.close()
        gate.open()
        do {
            _ = try await read.value
            XCTFail("A late connection must not revive a closed reader")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(stub(fresh).closeCount, 1)
        XCTAssertTrue(stub(fresh).offsets.isEmpty)
        do {
            _ = try await reader.read(offset: 0, length: 1)
            XCTFail("Closed reader must remain closed")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reconnectCount, 1)
    }

    func testAReadRetriesOnlyOnce() async throws {
        let stale = resources { _, _ in throw ConnectionError.disconnected }
        let fresh = resources { _, _ in throw ConnectionError.disconnected }
        var reconnectCount = 0
        let reader = ManagedSMBRemoteFileReader(resources: stale) {
            reconnectCount += 1
            return fresh
        }
        do {
            _ = try await reader.read(offset: 0, length: 1)
            XCTFail("Repeated failure must be returned instead of looping")
        } catch { XCTAssertTrue(error is ConnectionError) }
        XCTAssertEqual(reconnectCount, 1)
        XCTAssertEqual(stub(stale).offsets.count, 1)
        XCTAssertEqual(stub(fresh).offsets.count, 1)
        try await reader.close()
    }

    func testFailedReconnectDoesNotPoisonLaterReads() async throws {
        let stale = resources { _, _ in throw ConnectionError.disconnected }
        let fresh = resources { _, _ in Data([1]) }
        var reconnectCount = 0
        let reader = ManagedSMBRemoteFileReader(resources: stale) {
            reconnectCount += 1
            if reconnectCount == 1 { throw ConnectionError.connectionTimeout }
            return fresh
        }
        do {
            _ = try await reader.read(offset: 0, length: 1)
            XCTFail("First reconnect is expected to fail")
        } catch { XCTAssertTrue(error is ConnectionError) }
        let data = try await reader.read(offset: 0, length: 1)
        XCTAssertEqual(data, Data([1]))
        XCTAssertEqual(reconnectCount, 2)
        try await reader.close()
    }

    func testChangedFileSizeRejectsOldArchiveOffsets() async throws {
        let stale = resources(size: 100) { _, _ in throw ConnectionError.disconnected }
        let fresh = resources(size: 200) { _, _ in Data([1]) }
        let reader = ManagedSMBRemoteFileReader(resources: stale) { fresh }
        let size = try await reader.fileSize
        XCTAssertEqual(size, 100)
        do {
            _ = try await reader.read(offset: 0, length: 1)
            XCTFail("A changed archive must not be read with its old page index")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileReadCorruptFile) }
        XCTAssertTrue(stub(fresh).offsets.isEmpty)
        XCTAssertEqual(stub(fresh).closeCount, 1)
        try await reader.close()
    }

    private func resources(
        size: UInt64 = 1_024,
        read: @escaping (UInt64, UInt32) async throws -> Data
    ) -> ManagedSMBRemoteFileReader.Resources {
        let client = StubSMBClient(host: "127.0.0.1")
        return ManagedSMBRemoteFileReader.Resources(
            client: client,
            fileReader: StubSMBFileReader(session: client.session, size: size, read: read)
        )
    }

    private func stub(_ resources: ManagedSMBRemoteFileReader.Resources) -> StubSMBFileReader {
        resources.fileReader as! StubSMBFileReader
    }

    private func smbError(_ code: ErrorCode) -> ErrorResponse {
        var data = Data(count: 72)
        var status = code.rawValue.littleEndian
        withUnsafeBytes(of: &status) { data.replaceSubrange(8..<12, with: $0) }
        return ErrorResponse(data: data)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("SMB test did not reach the expected state")
                throw ConnectionError.connectionTimeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class StubSMBClient: SMBClient {
    nonisolated override init(host: String, connectTimeout: TimeInterval = 30) {
        super.init(host: host, connectTimeout: connectTimeout)
    }

    nonisolated override init(host: String, port: Int, connectTimeout: TimeInterval = 30) {
        super.init(host: host, port: port, connectTimeout: connectTimeout)
    }

    // Keep cleanup entirely local too; cancelling an unstarted NWConnection is asynchronous.
    override func disconnectShare() async throws -> TreeDisconnect.Response { throw CancellationError() }
    override func logoff() async throws -> Logoff.Response { throw CancellationError() }
}

@MainActor
private final class StubSMBFileReader: FileReader {
    let size: UInt64
    let readHandler: (UInt64, UInt32) async throws -> Data
    var offsets: [UInt64] = []
    var lengths: [UInt32] = []
    var closeCount = 0

    init(session: Session, size: UInt64, read: @escaping (UInt64, UInt32) async throws -> Data) {
        self.size = size
        self.readHandler = read
        super.init(session: session, path: "test.cbz")
    }

    override var fileSize: UInt64 { get async throws { size } }

    override func read(offset: UInt64, length: UInt32) async throws -> Data {
        offsets.append(offset)
        lengths.append(length)
        return try await readHandler(offset, length)
    }

    override func close() async throws { closeCount += 1 }
}

@MainActor
private final class SMBTestGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
