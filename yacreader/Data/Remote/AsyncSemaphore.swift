actor AsyncSemaphore {
    private let maxConcurrent: Int
    private var currentCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func wait() async {
        if currentCount < maxConcurrent {
            currentCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
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
