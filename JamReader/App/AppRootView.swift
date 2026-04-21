import SwiftUI

struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies

    @AppStorage(AppNavigationStorageKeys.selectedTab) private var selectedTabRawValue = AppRootTab.library.rawValue
    @StateObject private var browseRemoteServerViewModel: RemoteServerListViewModel
    @State private var browseEditorDraft: RemoteServerEditorDraft?
    @State private var rootTabBarHeight: CGFloat = AppLayout.bottomBarHeight

    init(viewModel: LibraryListViewModel, dependencies: AppDependencies) {
        self.viewModel = viewModel
        self.dependencies = dependencies
        _browseRemoteServerViewModel = StateObject(
            wrappedValue: RemoteServerListViewModel(
                profileStore: dependencies.remoteServerProfileStore,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
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

                if usesUIKitTabBarRoot {
                    AppRootTabBarControllerView(
                        selection: selectedTab,
                        tabBarHeight: $rootTabBarHeight,
                        libraryRoot: AnyView(
                            LibraryHomeView(viewModel: viewModel, dependencies: dependencies)
                                .background(Color.surfaceGrouped.ignoresSafeArea())
                        ),
                        browseRoot: AnyView(
                            BrowseHomeView(
                                dependencies: dependencies,
                                viewModel: browseRemoteServerViewModel,
                                editorDraft: $browseEditorDraft
                            )
                            .background(Color.surfaceGrouped.ignoresSafeArea())
                        ),
                        settingsRoot: AnyView(
                            SettingsHomeView(viewModel: viewModel, dependencies: dependencies)
                                .background(Color.surfaceGrouped.ignoresSafeArea())
                        )
                    )
                    .ignoresSafeArea()
                } else {
                    appTabView
                }
            }
            .overlay(alignment: .bottom) {
                RootImportOverlayHost(
                    controller: dependencies.remoteBackgroundImportController
                )
                    .padding(.horizontal, Spacing.sm)
                    .padding(
                        .bottom,
                        proxy.safeAreaInsets.bottom + effectiveBottomBarHeight - Spacing.xxs
                    )
            }
        }
        .background {
            SystemSheetPresenter(item: $browseEditorDraft) { draft in
                browseRemoteServerEditor(for: draft)
            }
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

    private var usesUIKitTabBarRoot: Bool {
        horizontalSizeClass == .regular
    }

    private var effectiveBottomBarHeight: CGFloat {
        usesUIKitTabBarRoot ? rootTabBarHeight : AppLayout.bottomBarHeight
    }

    private func browseRemoteServerEditor(
        for draft: RemoteServerEditorDraft
    ) -> some View {
        RemoteServerEditorSheet(
            draft: draft,
            appliesSwiftUIPresentationModifiers: false
        ) { updatedDraft in
            let alertState = browseRemoteServerViewModel.save(draft: updatedDraft)
            if alertState == nil {
                browseEditorDraft = nil
            }
            return alertState
        }
        .id(draft.id)
    }

    private var appTabView: some View {
        TabView(selection: selectedTab) {
            LibraryHomeView(viewModel: viewModel, dependencies: dependencies)
                .background(Color.surfaceGrouped.ignoresSafeArea())
                .tabItem {
                    Label("Library", systemImage: AppRootTab.library.systemImage)
                }
                .tag(AppRootTab.library)

            BrowseHomeView(
                dependencies: dependencies,
                viewModel: browseRemoteServerViewModel,
                editorDraft: $browseEditorDraft
            )
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
