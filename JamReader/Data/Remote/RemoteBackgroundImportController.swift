import Combine
import Foundation

@MainActor
final class RemoteBackgroundImportController: ObservableObject {
    @Published private(set) var activeProgress: RemoteBrowserProgressState?
    @Published var feedback: RemoteBrowserFeedbackState?

    private static let minimumProgressPublishInterval: Duration = .milliseconds(180)

    private var activeTask: Task<Void, Never>?
    private var activeCancellationController: RemoteImportCancellationController?
    private var pendingProgressCommitTask: Task<Void, Never>?
    private var pendingProgressState: RemoteBrowserProgressState?
    private var lastPublishedProgressState: RemoteBrowserProgressState?
    private var lastProgressPublishInstant: ContinuousClock.Instant?
    private let progressClock = ContinuousClock()

    var isImportRunning: Bool {
        activeTask != nil
    }

    var canCancelActiveImport: Bool {
        activeCancellationController != nil && (activeProgress?.isCancellable ?? false)
    }

    func start(
        operation: @escaping @MainActor (
            RemoteBackgroundImportController,
            RemoteImportCancellationController
        ) async -> Void
    ) -> Bool {
        guard activeTask == nil else {
            return false
        }

        feedback = nil
        let cancellationController = RemoteImportCancellationController()
        activeCancellationController = cancellationController
        activeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await operation(self, cancellationController)
            self.activeTask = nil
            self.activeCancellationController = nil
            self.clearActiveProgress()
        }
        return true
    }

    func setActiveProgress(
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        isCancellable: Bool = false
    ) {
        let nextState = RemoteBrowserProgressState(
            title: title,
            detail: detail,
            fraction: fraction,
            isCancellable: isCancellable
        )

        guard nextState != activeProgress, nextState != pendingProgressState else {
            return
        }

        let publishImmediately = shouldPublishProgressImmediately(nextState)
        if publishImmediately {
            commitProgress(nextState)
            return
        }

        pendingProgressState = nextState
        guard pendingProgressCommitTask == nil else {
            return
        }

        pendingProgressCommitTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: Self.minimumProgressPublishInterval)
            guard !Task.isCancelled, let pendingProgressState = self.pendingProgressState else {
                self.pendingProgressCommitTask = nil
                return
            }

            self.pendingProgressCommitTask = nil
            self.commitProgress(pendingProgressState)
        }
    }

    func clearActiveProgress() {
        pendingProgressCommitTask?.cancel()
        pendingProgressCommitTask = nil
        pendingProgressState = nil
        lastPublishedProgressState = nil
        lastProgressPublishInstant = nil
        activeProgress = nil
    }

    func presentFeedback(_ feedback: RemoteBrowserFeedbackState) {
        self.feedback = feedback
    }

    func dismissFeedback() {
        feedback = nil
    }

    func cancelActiveImport() {
        activeCancellationController?.cancel()
        activeTask?.cancel()

        guard activeProgress?.isCancellable == true else {
            return
        }

        activeProgress = RemoteBrowserProgressState(
            title: "Canceling Import",
            detail: "Stopping the current remote import…",
            fraction: activeProgress?.fraction,
            isCancellable: false
        )
        lastPublishedProgressState = activeProgress
        lastProgressPublishInstant = progressClock.now
        pendingProgressCommitTask?.cancel()
        pendingProgressCommitTask = nil
        pendingProgressState = nil
    }

    private func shouldPublishProgressImmediately(
        _ nextState: RemoteBrowserProgressState
    ) -> Bool {
        guard let lastPublishedProgressState else {
            return true
        }

        if lastPublishedProgressState.title != nextState.title
            || lastPublishedProgressState.isCancellable != nextState.isCancellable
            || lastPublishedProgressState.fraction == nil
            || nextState.fraction == nil
            || nextState.fraction == 1
            || activeProgress == nil {
            return true
        }

        if let lastProgressPublishInstant,
           progressClock.now - lastProgressPublishInstant >= Self.minimumProgressPublishInterval {
            return true
        }

        return false
    }

    private func commitProgress(_ progressState: RemoteBrowserProgressState) {
        pendingProgressCommitTask?.cancel()
        pendingProgressCommitTask = nil
        pendingProgressState = nil
        activeProgress = progressState
        lastPublishedProgressState = progressState
        lastProgressPublishInstant = progressClock.now
    }
}

final class RemoteImportCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func checkCancelled() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()

        if cancelled {
            throw CancellationError()
        }
    }
}
