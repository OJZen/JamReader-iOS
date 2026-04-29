import SwiftUI

struct AppRootOverlayView: View {
    @ObservedObject var controller: RemoteBackgroundImportController
    let bottomBarHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()

                RootImportOverlayHost(controller: controller)
                    .padding(.horizontal, Spacing.sm)
                    .padding(
                        .bottom,
                        proxy.safeAreaInsets.bottom + bottomBarHeight - Spacing.xxs
                    )
            }
        }
        .allowsHitTesting(true)
    }
}

private struct RootImportOverlayHost: View {
    @ObservedObject var controller: RemoteBackgroundImportController

    @State private var importFeedbackDismissTask: Task<Void, Never>?
    @State private var isImportProgressExpanded = true

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if let activeProgress = controller.activeProgress {
                RemoteBrowserCollapsibleImportProgressView(
                    progress: activeProgress,
                    isExpanded: $isImportProgressExpanded,
                    onCancel: controller.canCancelActiveImport
                        ? { controller.cancelActiveImport() }
                        : nil
                )
            }

            if let feedback = controller.feedback {
                RemoteBrowserFeedbackCard(
                    feedback: feedback,
                    onPrimaryAction: feedback.primaryAction.map { action in
                        {
                            controller.dismissFeedback()
                            handleAppAlertAction(action)
                        }
                    },
                    onDismiss: {
                        controller.dismissFeedback()
                    }
                )
            }
        }
        .onChange(of: controller.feedback?.id) { _, _ in
            scheduleImportFeedbackDismissalIfNeeded()
        }
        .onChange(of: controller.activeProgress != nil) { _, hasActiveProgress in
            if hasActiveProgress {
                withAnimation(AppAnimation.overlayPop) {
                    isImportProgressExpanded = true
                }
            } else {
                isImportProgressExpanded = true
            }
        }
        .onDisappear {
            importFeedbackDismissTask?.cancel()
            importFeedbackDismissTask = nil
        }
    }

    private func scheduleImportFeedbackDismissalIfNeeded() {
        importFeedbackDismissTask?.cancel()

        guard let feedback = controller.feedback,
              let autoDismissAfter = feedback.autoDismissAfter else {
            importFeedbackDismissTask = nil
            return
        }

        importFeedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else {
                return
            }

            controller.dismissFeedback()
            importFeedbackDismissTask = nil
        }
    }

    private func handleAppAlertAction(_ action: AppAlertAction) {
        switch action {
        case .openLibrary(let libraryID, let folderID):
            AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
        }
    }
}
