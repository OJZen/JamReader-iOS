import Foundation

actor AsyncSemaphore {
    private struct Waiter {
        let id: UUID
        let priority: UInt8
        let continuation: CheckedContinuation<Void, Error>
    }

    private let maxConcurrent: Int
    private var currentCount: Int = 0
    private var waiters: [Waiter] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    /// Acquires the semaphore. Higher-priority callers jump ahead of lower-priority ones
    /// already waiting, so interactive work is never starved by background prefetch.
    /// Throws `CancellationError` without taking a slot when the task is cancelled first.
    func wait(priority: TaskPriority = .medium) async throws {
        try Task.checkCancellation()
        if currentCount < maxConcurrent {
            currentCount += 1
            return
        }
        let id = UUID()
        let raw = priority.rawValue
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                // Insert in descending priority order so the highest-priority waiter
                // is always at index 0 and gets the next available slot.
                let insertIndex = waiters.firstIndex(where: { $0.priority < raw }) ?? waiters.endIndex
                waiters.insert(Waiter(id: id, priority: raw, continuation: continuation), at: insertIndex)
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume()
        } else {
            currentCount -= 1
        }
    }

    /// Acquires the semaphore, runs `operation`, and signals on completion.
    /// Uses `defer` so the semaphore is always released — even on cancellation.
    /// Returns `nil` without running `operation` when cancelled before acquiring.
    func run<T>(_ operation: @Sendable () async -> T?) async -> T? {
        guard (try? await wait()) != nil else {
            return nil
        }
        defer { signal() }
        return await operation()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
