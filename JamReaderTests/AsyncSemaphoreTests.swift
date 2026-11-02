import XCTest
@testable import JamReader

final class AsyncSemaphoreTests: XCTestCase {
    func testCancellingAQueuedWaiterThrowsAndLeavesTheSlotUsable() async throws {
        let semaphore = AsyncSemaphore(maxConcurrent: 1)
        try await semaphore.wait()

        let queued = Task { try await semaphore.wait() }
        try await Task.sleep(for: .milliseconds(50))
        queued.cancel()
        await assertCancelled(queued)

        await semaphore.signal()
        await assertAcquires(semaphore)
    }

    func testCancelledTaskDoesNotTakeAFreeSlot() async throws {
        let semaphore = AsyncSemaphore(maxConcurrent: 1)
        let started = expectation(description: "The task reaches the semaphore cancelled")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            started.fulfill()
            try await semaphore.wait()
        }
        await fulfillment(of: [started], timeout: 1)
        await assertCancelled(cancelled)

        await assertAcquires(semaphore)
    }

    func testSignalResumesQueuedWaitersByPriority() async throws {
        let semaphore = AsyncSemaphore(maxConcurrent: 1)
        try await semaphore.wait()
        let recorder = OrderRecorder()

        let background = Task {
            try await semaphore.wait(priority: .utility)
            await recorder.record("background")
        }
        try await Task.sleep(for: .milliseconds(50))
        let interactive = Task {
            try await semaphore.wait(priority: .userInitiated)
            await recorder.record("interactive")
            await semaphore.signal()
        }
        try await Task.sleep(for: .milliseconds(50))

        await semaphore.signal()
        try await interactive.value
        try await background.value

        let order = await recorder.values
        XCTAssertEqual(order, ["interactive", "background"])
    }

    func testRunSkipsTheOperationWhenCancelledWhileQueued() async throws {
        let semaphore = AsyncSemaphore(maxConcurrent: 1)
        try await semaphore.wait()
        let recorder = OrderRecorder()

        let queued = Task {
            await semaphore.run { () -> Int? in
                await recorder.record("ran")
                return 1
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        queued.cancel()

        let result = await queued.value
        let order = await recorder.values
        XCTAssertNil(result)
        XCTAssertEqual(order, [])
    }

    private func assertAcquires(_ semaphore: AsyncSemaphore) async {
        let acquired = expectation(description: "The semaphore has a free slot")
        let acquiring = Task {
            try await semaphore.wait()
            acquired.fulfill()
        }
        await fulfillment(of: [acquired], timeout: 1)
        acquiring.cancel()
    }

    private func assertCancelled(
        _ task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected the task to be cancelled", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, file: file, line: line)
        }
    }
}

private actor OrderRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}
