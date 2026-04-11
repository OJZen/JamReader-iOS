actor AsyncSemaphore {
    private let maxConcurrent: Int
    private var currentCount: Int = 0
    private var waiters: [(priority: UInt8, continuation: CheckedContinuation<Void, Never>)] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    /// Acquires the semaphore. Higher-priority callers jump ahead of lower-priority ones
    /// already waiting, so interactive work is never starved by background prefetch.
    func wait(priority: TaskPriority = .medium) async {
        if currentCount < maxConcurrent {
            currentCount += 1
            return
        }
        let raw = priority.rawValue
        await withCheckedContinuation { continuation in
            // Insert in descending priority order so the highest-priority waiter
            // is always at index 0 and gets the next available slot.
            let insertIndex = waiters.firstIndex(where: { $0.priority < raw }) ?? waiters.endIndex
            waiters.insert((priority: raw, continuation: continuation), at: insertIndex)
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
    func run<T>(_ operation: @Sendable () async -> T) async -> T {
        await wait()
        defer { signal() }
        return await operation()
    }
}
