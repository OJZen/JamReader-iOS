import Combine
import Foundation

@MainActor
final class RemoteBackgroundImportController: ObservableObject {
    @Published private(set) var activeProgress: RemoteBrowserProgressState?
    @Published var feedback: RemoteBrowserFeedbackState?

    private var activeTask: Task<Void, Never>?
    private var activeCancellationController: RemoteImportCancellationController?

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
            self.activeProgress = nil
        }
        return true
    }

    func setActiveProgress(
        title: String,
        detail: String? = nil,
        fraction: Double? = nil,
        isCancellable: Bool = false
    ) {
        activeProgress = RemoteBrowserProgressState(
            title: title,
            detail: detail,
            fraction: fraction,
            isCancellable: isCancellable
        )
    }

    func clearActiveProgress() {
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
