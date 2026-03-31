import SwiftUI

struct AppRootView: View {
    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies
    @ObservedObject private var remoteBackgroundImportController: RemoteBackgroundImportController

    @AppStorage(AppNavigationStorageKeys.selectedTab) private var selectedTabRawValue = AppRootTab.library.rawValue
    @State private var importFeedbackDismissTask: Task<Void, Never>?
    @State private var isImportProgressExpanded = true

    init(viewModel: LibraryListViewModel, dependencies: AppDependencies) {
        self.viewModel = viewModel
        self.dependencies = dependencies
        _remoteBackgroundImportController = ObservedObject(
            wrappedValue: dependencies.remoteBackgroundImportController
        )
    }

    private var selectedTab: Binding<AppRootTab> {
        Binding(
            get: { AppRootTab(rawValue: selectedTabRawValue) ?? .library },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.surfaceGrouped
                    .ignoresSafeArea()

                TabView(selection: selectedTab) {
                    LibraryHomeView(viewModel: viewModel, dependencies: dependencies)
                        .background(Color.surfaceGrouped.ignoresSafeArea())
                        .tabItem {
                            Label("Library", systemImage: AppRootTab.library.systemImage)
                        }
                        .tag(AppRootTab.library)

                    BrowseHomeView(dependencies: dependencies)
                        .background(Color.surfaceGrouped.ignoresSafeArea())
                        .tabItem {
                            Label("Browse", systemImage: AppRootTab.browse.systemImage)
                        }
                        .tag(AppRootTab.browse)

                    SettingsHomeView(viewModel: viewModel, dependencies: dependencies)
                        .background(Color.surfaceGrouped.ignoresSafeArea())
                        .tabItem {
                            Label("Settings", systemImage: AppRootTab.settings.systemImage)
                        }
                        .tag(AppRootTab.settings)
                }
                .background(Color.surfaceGrouped.ignoresSafeArea())
            }
            .overlay(alignment: .bottom) {
                rootImportOverlay
                    .padding(.horizontal, Spacing.sm)
                    .padding(
                        .bottom,
                        proxy.safeAreaInsets.bottom + AppLayout.bottomBarHeight - Spacing.xxs
                    )
            }
        }
        .onChange(of: remoteBackgroundImportController.feedback?.id) { _, _ in
            scheduleImportFeedbackDismissalIfNeeded()
        }
        .onChange(of: remoteBackgroundImportController.activeProgress != nil) { _, hasActiveProgress in
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
        // iPad keyboard shortcuts: Cmd+1/2/3 for tab switching
        .background {
            VStack {
                Button("") { selectedTab.wrappedValue = .library }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab.wrappedValue = .browse }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab.wrappedValue = .settings }
                    .keyboardShortcut("3", modifiers: .command)
            }
            .allowsHitTesting(false)
            .opacity(0)
        }
    }

    @ViewBuilder
    private var rootImportOverlay: some View {
        VStack(spacing: Spacing.sm) {
            if let activeProgress = remoteBackgroundImportController.activeProgress {
                RemoteBrowserCollapsibleImportProgressView(
                    progress: activeProgress,
                    isExpanded: $isImportProgressExpanded,
                    onCancel: remoteBackgroundImportController.canCancelActiveImport
                        ? { remoteBackgroundImportController.cancelActiveImport() }
                        : nil
                )
            }

            if let feedback = remoteBackgroundImportController.feedback {
                RemoteBrowserFeedbackCard(
                    feedback: feedback,
                    onPrimaryAction: feedback.primaryAction.map { action in
                        {
                            remoteBackgroundImportController.dismissFeedback()
                            handleAppAlertAction(action)
                        }
                    },
                    onDismiss: {
                        remoteBackgroundImportController.dismissFeedback()
                    }
                )
            }
        }
    }

    private func scheduleImportFeedbackDismissalIfNeeded() {
        importFeedbackDismissTask?.cancel()

        guard let feedback = remoteBackgroundImportController.feedback,
              let autoDismissAfter = feedback.autoDismissAfter else {
            importFeedbackDismissTask = nil
            return
        }

        importFeedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else {
                return
            }

            remoteBackgroundImportController.dismissFeedback()
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
