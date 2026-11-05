import XCTest
@testable import JamReader

@MainActor
final class ReaderPageLoadGateTests: XCTestCase {
    func testThirdLoadWaitsUntilOneOfTwoPermitsIsReturned() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 2)
        try await gate.wait()
        try await gate.wait()
        var acquired = false
        let third = await enqueue(gate) { acquired = true }
        XCTAssertFalse(acquired)

        gate.signal()
        try await third.value
        XCTAssertTrue(acquired)
        gate.signal()
        gate.signal()
    }

    func testWaitersResumeInFIFOOrder() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 1)
        try await gate.wait()
        var order: [Int] = []
        let first = await enqueue(gate) { order.append(1) }
        let second = await enqueue(gate) { order.append(2) }
        let third = await enqueue(gate) { order.append(3) }

        gate.signal()
        try await first.value
        XCTAssertEqual(order, [1])
        gate.signal()
        try await second.value
        XCTAssertEqual(order, [1, 2])
        gate.signal()
        try await third.value
        XCTAssertEqual(order, [1, 2, 3])
        gate.signal()
    }

    func testCancellingAWaiterRemovesItWithoutTakingAPermit() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 1)
        try await gate.wait()
        let cancelled = await enqueue(gate)
        let next = await enqueue(gate)
        cancelled.cancel()
        await assertCancelled(cancelled)

        gate.signal()
        try await next.value
        gate.signal()
        try await gate.wait()
        gate.signal()
    }

    func testAlreadyCancelledTaskDoesNotTakeAFreePermit() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 1)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await gate.wait()
        }
        await assertCancelled(cancelled)

        try await gate.wait()
        gate.signal()
    }

    func testCancellationAfterGrantStillReturnsThePermit() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 1)
        try await gate.wait()
        let entered = expectation(description: "The load enters the gate")
        let cancelled = Task {
            entered.fulfill()
            try await gate.wait()
            defer { gate.signal() }
            try Task.checkCancellation()
        }
        await fulfillment(of: [entered], timeout: 1)

        gate.signal()
        cancelled.cancel()
        await assertCancelled(cancelled)
        try await gate.wait()
        gate.signal()
    }

    func testSuspendedGateWaitsForTheCurrentLoadToFinish() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 2, isSuspended: true)
        var acquired = 0
        let first = await enqueue(gate) { acquired += 1 }
        let second = await enqueue(gate) { acquired += 1 }
        XCTAssertEqual(acquired, 0)

        gate.isSuspended = false
        try await first.value
        try await second.value
        XCTAssertEqual(acquired, 2)
        gate.signal()
        gate.signal()
    }

    func testReturningAPermitWhileSuspendedDoesNotStartAnotherLoad() async throws {
        let gate = ReaderPageLoadGate(maxConcurrent: 1)
        try await gate.wait()
        var acquired = false
        let next = await enqueue(gate) { acquired = true }
        gate.isSuspended = true
        gate.signal()
        XCTAssertFalse(acquired)

        gate.isSuspended = false
        try await next.value
        XCTAssertTrue(acquired)
        gate.signal()
    }

    private func enqueue(
        _ gate: ReaderPageLoadGate,
        onAcquired: @escaping @MainActor () -> Void = {}
    ) async -> Task<Void, Error> {
        let entered = expectation(description: "The load enters the gate")
        let task = Task { @MainActor in
            entered.fulfill()
            try await gate.wait()
            onAcquired()
        }
        await fulfillment(of: [entered], timeout: 1)
        return task
    }

    private func assertCancelled(
        _ task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected cancellation", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, file: file, line: line)
        }
    }
}
