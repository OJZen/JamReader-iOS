import SwiftUI

struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var viewModel: LibraryListViewModel
    let dependencies: AppDependencies
    @ObservedObject private var remoteBackgroundImportController: RemoteBackgroundImportController

    @AppStorage(AppNavigationStorageKeys.selectedTab) private var selectedTabRawValue = AppRootTab.library.rawValue
    @State private var importFeedbackDismissTask: Task<Void, Never>?
    @State private var isImportProgressExpanded = true
    @StateObject private var browseRemoteServerViewModel: RemoteServerListViewModel
    @State private var browseEditorDraft: RemoteServerEditorDraft?
    @State private var rootTabBarHeight: CGFloat = AppLayout.bottomBarHeight

    init(viewModel: LibraryListViewModel, dependencies: AppDependencies) {
        self.viewModel = viewModel
        self.dependencies = dependencies
        _remoteBackgroundImportController = ObservedObject(
            wrappedValue: dependencies.remoteBackgroundImportController
        )
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
                rootImportOverlay
                    .padding(.horizontal, Spacing.sm)
                    .padding(
                        .bottom,
                        proxy.safeAreaInsets.bottom + effectiveBottomBarHeight - Spacing.xxs
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
