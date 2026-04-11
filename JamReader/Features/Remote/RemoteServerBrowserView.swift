import Combine
import SwiftUI
import UIKit

struct RemoteServerBrowserView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerBrowserViewModel
    @State private var displayMode: LibraryComicDisplayMode = .list
    @State private var hasConfiguredDisplayMode = false
    @State private var sortMode: RemoteDirectorySortMode = .nameAscending
    @State private var hasConfiguredSortMode = false
    @State private var importRequest: RemoteBrowserImportRequest?
    @State private var navigationRequest: RemoteBrowserNavigationRequest?
    @State private var presentedComicItem: RemoteComicOpenItem?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?
    @State private var lastDismissRefreshItem: RemoteDirectoryItem?
    @State private var pendingOfflineRemoval: PendingRemoteOfflineRemoval?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @StateObject private var visibilityTracker = RemoteComicVisibilityTracker()
    @State private var displaySnapshot = RemoteBrowserDisplaySnapshot.empty
    @State private var renderedSections: [RemoteBrowserListSectionModel] = []
    @State private var thumbnailPreheatTask: Task<Void, Never>?
    @State private var thumbnailPreheatDebounceTask: Task<Void, Never>?
    @State private var displaySnapshotRefreshTask: Task<Void, Never>?
    @State private var sectionBuildDebounceTask: Task<Void, Never>?
    @State private var sectionBuildTask: Task<Void, Never>?
    @State private var isDisplaySnapshotRefreshing = false
    @State private var isSectionBuildRefreshing = false
    @State private var presentedInfoItem: RemoteDirectoryItem?
    @State private var browserContainerWidth: CGFloat = 0

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        initialDisplayMode: LibraryComicDisplayMode? = nil,
        initialSortMode: RemoteDirectorySortMode? = nil,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        let storedDisplayMode = dependencies.remoteBrowserPreferencesStore.storedDisplayMode(for: profile.id)
        let resolvedDisplayMode = initialDisplayMode ?? storedDisplayMode ?? .list
        let resolvedSortMode = initialSortMode ?? dependencies.remoteBrowserPreferencesStore.loadSortMode(for: profile.id)
        _displayMode = State(initialValue: resolvedDisplayMode)
        _hasConfiguredDisplayMode = State(initialValue: initialDisplayMode != nil || storedDisplayMode != nil)
        _sortMode = State(initialValue: resolvedSortMode)
        _hasConfiguredSortMode = State(initialValue: true)
        _viewModel = StateObject(
            wrappedValue: RemoteServerBrowserViewModel(
                profile: profile,
                currentPath: currentPath,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore,
                importedComicsImportService: dependencies.importedComicsImportService,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                remoteBackgroundImportController: dependencies.remoteBackgroundImportController
            )
        )
    }

    var body: some View {
        browserPresentationLayer
    }

    private var browserBaseLayer: some View {
        browserContent
            .readContainerWidth(into: $browserContainerWidth)
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { browserToolbar }
            .background(browserBackground)
    }

    private var browserLifecycleLayer: some View {
        browserBaseLayer
            .task {
                await viewModel.loadIfNeeded()
            }
            .onAppear(perform: handleBrowserAppear)
            .onChange(of: viewModel.items) { _, _ in
                handleItemsChanged()
            }
            .onChange(of: sortMode) { _, _ in
                handleSortModeChanged()
            }
            .onChange(of: displaySnapshot) { _, _ in
                scheduleSectionBuild(immediately: true)
            }
            .onChange(of: viewModel.progressByItemID) { _, _ in
                scheduleSectionBuild()
            }
            .onChange(of: viewModel.cacheAvailabilityByItemID) { _, _ in
                scheduleSectionBuild()
            }
            .onChange(of: displayMode) { _, _ in
                scheduleThumbnailPreheat(immediately: true)
            }
            .onChange(of: displayScale) { _, _ in
                scheduleThumbnailPreheat(immediately: true)
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                scheduleThumbnailPreheat(immediately: true)
            }
            .onChange(of: browserContainerWidth) { _, newWidth in
                if !hasConfiguredDisplayMode, newWidth > 0 {
                    configureDisplayModeIfNeeded()
                }
                scheduleThumbnailPreheat(immediately: true)
            }
            .refreshable {
                await viewModel.load()
            }
            .onChange(of: viewModel.feedback?.id) { _, _ in
                scheduleFeedbackDismissalIfNeeded()
            }
            .onDisappear(perform: handleBrowserDisappear)
    }

    private var browserPresentationLayer: some View {
        browserLifecycleLayer
            .overlay(alignment: .bottom) {
                browserBottomOverlay
            }
            .alert(item: $viewModel.alert, content: browserAlert)
            .confirmationDialog(
                pendingOfflineRemoval?.title ?? "Remove downloaded copies?",
                isPresented: pendingOfflineRemovalDialogBinding,
                titleVisibility: .visible
            ) {
                offlineRemovalDialogActions
            } message: {
                offlineRemovalDialogMessage
            }
            .sheet(item: $importRequest, content: importSheet)
            .navigationDestination(item: $navigationRequest, destination: navigationDestination)
            .background(readerPresenter)
            .background {
                SystemSheetPresenter(item: $presentedInfoItem, content: browserInfoSheet)
            }
    }

    private var pendingOfflineRemovalDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingOfflineRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingOfflineRemoval = nil
                }
            }
        )
    }

    @ViewBuilder
    private var offlineRemovalDialogActions: some View {
        if let pendingOfflineRemoval {
            Button(pendingOfflineRemoval.buttonTitle, role: .destructive) {
                viewModel.removeOfflineCopies(for: pendingOfflineRemoval.items)
                self.pendingOfflineRemoval = nil
            }
        }

        Button("Cancel", role: .cancel) {
            pendingOfflineRemoval = nil
        }
    }

    @ViewBuilder
    private var offlineRemovalDialogMessage: some View {
        if let pendingOfflineRemoval {
            Text(pendingOfflineRemoval.message)
        }
    }

    private func browserAlert(for alert: AppAlertState) -> Alert {
        makeRemoteAlert(for: alert, onPrimaryAction: handleAppAlertAction(_:))
    }

    private func handleBrowserAppear() {
        viewModel.refreshProgressState()
        viewModel.refreshShortcutState()
        if browserContainerWidth > 0 {
            configureDisplayModeIfNeeded()
        }
        configureSortModeIfNeeded()
        scheduleDisplaySnapshotRefresh()
        scheduleThumbnailPreheat(immediately: true)
    }

    private func handleItemsChanged() {
        scheduleDisplaySnapshotRefresh()
        scheduleThumbnailPreheat(immediately: true)
    }

    private func handleSortModeChanged() {
        scheduleDisplaySnapshotRefresh()
        scheduleThumbnailPreheat(immediately: true)
    }

    private func handleBrowserDisappear() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        cancelThumbnailPreheat()
        cancelBrowserBuildTasks()
        visibilityTracker.reset()
    }

    private var browserBackground: some View {
        Color.surfaceGrouped
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var browserBottomOverlay: some View {
        if viewModel.activeProgress != nil || viewModel.feedback != nil {
            VStack(spacing: Spacing.sm) {
                if let activeProgress = viewModel.activeProgress {
                    RemoteBrowserImportProgressView(
                        progress: activeProgress,
                        onCancel: nil
                    )
                }

                if let feedback = viewModel.feedback {
                    RemoteBrowserFeedbackCard(
                        feedback: feedback,
                        onPrimaryAction: feedback.primaryAction.map { action in
                            {
                                viewModel.dismissFeedback()
                                handleAppAlertAction(action)
                            }
                        },
                        onDismiss: {
                            viewModel.dismissFeedback()
                        }
                    )
                }
            }
            .padding(.bottom, Spacing.xs)
        }
    }

    @ViewBuilder
    private var readerPresenter: some View {
        HeroReaderPresenter(
            item: $presentedComicItem,
            sourceFrame: heroSourceFrame,
            previewImage: heroPreviewImage,
            onDismiss: {
                heroSourceFrame = .zero
                heroPreviewImage = nil
                if let lastDismissRefreshItem {
                    viewModel.refreshProgressState(for: lastDismissRefreshItem)
                    self.lastDismissRefreshItem = nil
                } else {
                    viewModel.refreshProgressState()
                }
            }
        ) { open in
            RemoteComicLoadingView(
                profile: viewModel.profile,
                item: open.item,
                dependencies: dependencies,
                openMode: open.mode,
                referenceOverride: open.referenceOverride
            )
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if displayMode == .grid {
            gridBody
        } else {
            listBody
        }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                let newMode: LibraryComicDisplayMode = displayMode == .list ? .grid : .list
                applyDisplayMode(newMode)
            } label: {
                Image(systemName: displayMode == .list ? "square.grid.2x2" : "list.bullet")
            }

            Menu {
                ForEach(RemoteDirectorySortMode.allCases) { mode in
                    Button {
                        applySortMode(mode)
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.systemImageName)

                            if sortMode == mode {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }

            Menu {
                Section {
                    Button {
                        viewModel.toggleCurrentFolderShortcut()
                    } label: {
                        Label(
                            viewModel.isCurrentFolderSaved ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: viewModel.isCurrentFolderSaved ? "star.fill" : "star"
                        )
                    }
                }

                if let parentPath = viewModel.parentPath {
                    Section("Navigate") {
                        Button {
                            navigationRequest = .directory(parentPath)
                        } label: {
                            Label("Up One Level", systemImage: "arrow.up.left")
                        }

                        if parentPath != viewModel.rootPath {
                            Button {
                                navigationRequest = .directory(viewModel.rootPath)
                            } label: {
                                Label("Go to Root", systemImage: "arrow.uturn.backward.circle")
                            }
                        }
                    }
                }

                if hasContextActions {
                    Section("Folder") {
                        if !displayedComicFiles.isEmpty {
                            Button {
                                Task<Void, Never> {
                                    await viewModel.saveComicsForOffline(displayedComicFiles)
                                }
                            } label: {
                                Label(saveVisibleComicsButtonTitle, systemImage: "icloud.and.arrow.down")
                            }
                        }

                        if !visibleOfflineComicFiles.isEmpty {
                            Button(role: .destructive) {
                                presentVisibleOfflineRemovalConfirmation()
                            } label: {
                                Label(removeVisibleOfflineCopiesButtonTitle, systemImage: "trash")
                            }
                        }

                        if viewModel.canImportCurrentFolderRecursively {
                            Button {
                                importRequest = .currentFolder
                            } label: {
                                Label(importCurrentFolderButtonTitle, systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func importSheet(for request: RemoteBrowserImportRequest) -> some View {
        switch request {
        case .comic:
            LibraryImportDestinationSheet(
                title: request.destinationPickerTitle,
                message: request.destinationPickerMessage,
                supplementaryNotice: ImportDestinationSheetCopy.remoteImportNotice,
                dependencies: dependencies,
                preferredSelection: nil
            ) { selection in
                startImportTask(
                    request,
                    destinationSelection: selection,
                    scope: .currentFolderOnly
                )
            }
        case .currentFolder, .directory:
            RemoteImportOptionsSheet(
                title: request.destinationPickerTitle,
                message: request.destinationPickerMessage,
                supplementaryNotice: ImportDestinationSheetCopy.remoteImportNotice,
                confirmLabel: "Import",
                availableScopes: availableImportScopes(for: request),
                defaultScope: defaultImportScope(for: request),
                dependencies: dependencies,
                preferredSelection: nil
            ) { selection, scope in
                startImportTask(
                    request,
                    destinationSelection: selection,
                    scope: scope
                )
            }
        }
    }

    @ViewBuilder
    private func navigationDestination(for request: RemoteBrowserNavigationRequest) -> some View {
        switch request {
        case .directory(let path):
            RemoteServerBrowserView(
                profile: viewModel.profile,
                currentPath: path,
                initialDisplayMode: displayMode,
                initialSortMode: sortMode,
                dependencies: dependencies
            )
        case .comic:
            EmptyView() // Comics are now presented via fullScreenCover
        }
    }

    private var listBody: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(message: "Connecting to Remote Library")
                    .padding(.vertical, Spacing.lg)
            } else if viewModel.loadIssue != nil {
                remoteErrorContent()
            } else if viewModel.items.isEmpty {
                browserUnavailableContent(
                    title: "No Remote Files",
                    systemImage: "folder",
                    description: emptyFolderDescription
                )
            } else if !hasVisibleItems {
                if isPreparingBrowserSnapshot {
                    LoadingStateView(message: "Preparing Remote Library")
                        .padding(.vertical, Spacing.lg)
                } else {
                    browserUnavailableContent(
                        title: "No Remote Files",
                        systemImage: "folder",
                        description: emptyFolderDescription
                    )
                }
            } else {
                GeometryReader { geometry in
                    RemoteServerBrowserListUIKitView(
                        sections: renderedSections,
                        profile: viewModel.profile,
                        browsingService: dependencies.remoteServerBrowsingService,
                        layoutContext: browserLayoutContext(for: geometry.size.width),
                        onVisibleComicIDsChanged: handleVisibleComicIDsChanged(_:),
                        onOpenItem: { item, sourceFrame in
                            if item.canOpenAsComic {
                                prepareHeroTransition(for: item, fallbackFrame: sourceFrame)
                            }
                            openPrimaryAction(for: item)
                        },
                        onShowInfo: { item in
                            presentInfoSheet(for: item)
                        },
                        onOpenOffline: { item in
                            openOfflineCopy(for: item)
                        },
                        onSaveOffline: { item in
                            saveOfflineAction(
                                for: item,
                                availability: viewModel.cacheAvailability(for: item)
                            )?()
                        },
                        onRemoveOffline: { item in
                            removeOfflineAction(
                                for: item,
                                availability: viewModel.cacheAvailability(for: item)
                            )?()
                        },
                        onImport: { item in
                            importAction(for: item)?()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .background(Color.surfaceGrouped)
                }
            }
        }
        .background(Color.surfaceGrouped)
    }

    private var gridBody: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(message: "Connecting to Remote Library")
                    .padding(.vertical, Spacing.lg)
            } else if viewModel.loadIssue != nil {
                remoteErrorContent()
            } else if viewModel.items.isEmpty {
                browserUnavailableContent(
                    title: "No Remote Files",
                    systemImage: "folder",
                    description: emptyFolderDescription
                )
            } else if !hasVisibleItems {
                if isPreparingBrowserSnapshot {
                    LoadingStateView(message: "Preparing Remote Library")
                        .padding(.vertical, Spacing.lg)
                } else {
                    browserUnavailableContent(
                        title: "No Remote Files",
                        systemImage: "folder",
                        description: emptyFolderDescription
                    )
                }
            } else {
                GeometryReader { geometry in
                    RemoteServerBrowserGridUIKitView(
                        sections: renderedSections,
                        profile: viewModel.profile,
                        browsingService: dependencies.remoteServerBrowsingService,
                        layoutContext: browserLayoutContext(for: geometry.size.width),
                        onVisibleComicIDsChanged: handleVisibleComicIDsChanged(_:),
                        onOpenItem: { item, sourceFrame in
                            if item.canOpenAsComic {
                                prepareHeroTransition(for: item, fallbackFrame: sourceFrame)
                            }
                            openPrimaryAction(for: item)
                        },
                        onShowInfo: { item in
                            presentInfoSheet(for: item)
                        },
                        onOpenOffline: { item in
                            openOfflineCopy(for: item)
                        },
                        onSaveOffline: { item in
                            saveOfflineAction(
                                for: item,
                                availability: viewModel.cacheAvailability(for: item)
                            )?()
                        },
                        onRemoveOffline: { item in
                            removeOfflineAction(
                                for: item,
                                availability: viewModel.cacheAvailability(for: item)
                            )?()
                        },
                        onImport: { item in
                            importAction(for: item)?()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .background(Color.surfaceGrouped)
                }
            }
        }
        .background(Color.surfaceGrouped)
    }

    private func remoteErrorContent() -> some View {
        let loadIssue = viewModel.loadIssue

        return ContentUnavailableView {
            Label(
                loadIssue?.title ?? "Remote Folder Unavailable",
                systemImage: "wifi.exclamationmark"
            )
            .font(AppFont.title2())
            .foregroundStyle(Color.appDanger)
        } description: {
            Text(loadIssue?.message ?? "This remote folder could not be opened.")
                .font(AppFont.callout())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        } actions: {
            errorRecoveryActions(loadIssue: loadIssue)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func errorRecoveryActions(loadIssue: RemoteBrowserLoadIssue?) -> some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            if let recoverySuggestion = loadIssue?.recoverySuggestion {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)

                    Text(recoverySuggestion)
                        .font(AppFont.footnote())
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: Spacing.sm) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if loadIssue?.prefersPathRecoveryActions == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        upOneLevelButton
                        sessionRootButton
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(spacing: Spacing.sm) {
                        upOneLevelButton
                        sessionRootButton
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var retryButton: some View {
        Button {
            Task<Void, Never> {
                await viewModel.load()
            }
        } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func manageServersButton(loadIssue: RemoteBrowserLoadIssue?) -> some View {
        if loadIssue?.showsManageServersAction == true {
            NavigationLink {
                RemoteServerListView(dependencies: dependencies)
            } label: {
                Label("Manage Servers", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var continueReadingButton: some View {
        if let recoverySession = viewModel.recoverySession,
           let loadIssue = viewModel.loadIssue,
           loadIssue.allowsOfflineRecovery {
            HeroTapButton { frame in
                openRecoverySession(recoverySession, fallbackFrame: frame)
            } label: {
                Label("Open Last Comic", systemImage: "book.closed")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var offlineShelfButton: some View {
        if let loadIssue = viewModel.loadIssue,
           loadIssue.allowsOfflineRecovery,
           viewModel.offlineRecoveryCount > 1 {
            NavigationLink {
                RemoteOfflineShelfView(dependencies: dependencies)
            } label: {
                Label("Offline Shelf", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var upOneLevelButton: some View {
        if let parentPath = viewModel.parentPath {
            Button {
                navigationRequest = .directory(parentPath)
            } label: {
                RemoteBrowserHeaderActionChip(
                    title: "Up",
                    systemImage: "arrow.up.left",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var sessionRootButton: some View {
        if let parentPath = viewModel.parentPath, parentPath != viewModel.rootPath {
            Button {
                navigationRequest = .directory(viewModel.rootPath)
            } label: {
                RemoteBrowserHeaderActionChip(
                    title: "Root",
                    systemImage: "arrow.uturn.backward.circle",
                    tint: .teal
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var hasContextActions: Bool {
        viewModel.canImportCurrentFolderRecursively
            || !displayedComicFiles.isEmpty
            || !visibleOfflineComicFiles.isEmpty
    }

    private func configureDisplayModeIfNeeded() {
        guard !hasConfiguredDisplayMode else {
            return
        }

        hasConfiguredDisplayMode = true
        displayMode = dependencies.remoteBrowserPreferencesStore.loadDisplayMode(
            for: viewModel.profile.id,
            defaultMode: defaultBrowserDisplayMode
        )
    }

    private var defaultBrowserDisplayMode: LibraryComicDisplayMode {
        let layoutContext = browserLayoutContext(for: browserContainerWidth)
        return layoutContext.usesMediumGridMetrics || layoutContext.usesWideGridMetrics ? .grid : .list
    }

    private func configureSortModeIfNeeded() {
        guard !hasConfiguredSortMode else {
            return
        }

        hasConfiguredSortMode = true
        sortMode = dependencies.remoteBrowserPreferencesStore.loadSortMode(
            for: viewModel.profile.id
        )
    }

    private func scheduleThumbnailPreheat(immediately: Bool = false) {
        cancelThumbnailPreheat()

        let items = displayedComicFiles.filter { !$0.isPDFDocument }
        guard displayMode == .grid, !items.isEmpty else {
            return
        }

        let visibleIDs = visibilityTracker.visibleIDs
        let plan = thumbnailPreheatPlan(
            visibleIDs: visibleIDs,
            items: items
        )
        let effectiveContainerWidth = browserContainerWidth > 0
            ? browserContainerWidth
            : UIScreen.main.bounds.width
        let estimatedItemWidth = browserLayoutContext(
            for: effectiveContainerWidth
        ).estimatedGridItemWidth
        let estimatedItemHeight = estimatedItemWidth / AppLayout.coverAspectRatio
        let maxPixelSize = Int(max(estimatedItemWidth, estimatedItemHeight) * max(displayScale, 1))

        let startPreheat = {
            thumbnailPreheatTask = Task(priority: .utility) {
                await preheatVisibleThumbnails(
                    items: items,
                    plan: plan,
                    maxPixelSize: maxPixelSize
                )
            }
        }

        if immediately {
            startPreheat()
            return
        }

        thumbnailPreheatDebounceTask = Task(priority: .utility) {
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }

                startPreheat()
                thumbnailPreheatDebounceTask = nil
            }
        }
    }

    private func cancelThumbnailPreheat() {
        thumbnailPreheatDebounceTask?.cancel()
        thumbnailPreheatDebounceTask = nil
        thumbnailPreheatTask?.cancel()
        thumbnailPreheatTask = nil
    }

    private func cancelBrowserBuildTasks() {
        displaySnapshotRefreshTask?.cancel()
        displaySnapshotRefreshTask = nil
        sectionBuildDebounceTask?.cancel()
        sectionBuildDebounceTask = nil
        sectionBuildTask?.cancel()
        sectionBuildTask = nil
        isDisplaySnapshotRefreshing = false
        isSectionBuildRefreshing = false
    }

    private func preheatVisibleThumbnails(
        items: [RemoteDirectoryItem],
        plan: ThumbnailPreheatPlan,
        maxPixelSize: Int
    ) async {
        guard displayMode == .grid, !items.isEmpty else {
            return
        }

        await preheatThumbnails(
            items: items,
            in: plan.primaryRange,
            maxPixelSize: maxPixelSize,
            concurrency: displayMode == .grid ? 2 : 1,
            allowsRemoteFetch: true
        )

        guard !Task.isCancelled else {
            return
        }

        for secondaryRange in plan.secondaryRanges {
            await preheatThumbnails(
                items: items,
                in: secondaryRange,
                maxPixelSize: maxPixelSize,
                concurrency: 1,
                allowsRemoteFetch: false
            )

            guard !Task.isCancelled else {
                return
            }
        }
    }

    private func thumbnailPreheatPlan(
        visibleIDs: Set<String>,
        items: [RemoteDirectoryItem]
    ) -> ThumbnailPreheatPlan {
        guard !items.isEmpty else {
            return ThumbnailPreheatPlan(
                primaryRange: 0..<0,
                secondaryRanges: []
            )
        }

        let visibleIndexes = items.enumerated().compactMap { index, item in
            visibleIDs.contains(item.id) ? index : nil
        }

        let defaultVisibleUpperBound = min(
            items.count - 1,
            displayMode == .grid ? 5 : 2
        )
        let visibleLowerBound = visibleIndexes.min() ?? 0
        let visibleUpperBound = visibleIndexes.max() ?? defaultVisibleUpperBound

        let primaryLeadingPadding = displayMode == .grid ? 10 : 4
        let primaryTrailingPadding = displayMode == .grid ? 4 : 1
        let secondaryLeadingPadding = displayMode == .grid ? 24 : 10
        let secondaryTrailingPadding = displayMode == .grid ? 8 : 2

        let primaryStart = max(0, visibleLowerBound - primaryTrailingPadding)
        let primaryEndExclusive = min(items.count, visibleUpperBound + primaryLeadingPadding + 1)
        let primaryRange = primaryStart..<primaryEndExclusive

        let secondaryStart = max(0, visibleLowerBound - secondaryTrailingPadding)
        let secondaryEndExclusive = min(items.count, visibleUpperBound + secondaryLeadingPadding + 1)

        var secondaryRanges: [Range<Int>] = []
        if secondaryStart < primaryRange.lowerBound {
            secondaryRanges.append(secondaryStart..<primaryRange.lowerBound)
        }
        if primaryRange.upperBound < secondaryEndExclusive {
            secondaryRanges.append(primaryRange.upperBound..<secondaryEndExclusive)
        }

        return ThumbnailPreheatPlan(
            primaryRange: primaryRange,
            secondaryRanges: secondaryRanges
        )
    }

    private func preheatThumbnails(
        items: [RemoteDirectoryItem],
        in range: Range<Int>,
        maxPixelSize: Int,
        concurrency: Int,
        allowsRemoteFetch: Bool
    ) async {
        guard !range.isEmpty else {
            return
        }

        await RemoteComicThumbnailPipeline.shared.preheat(
            for: viewModel.profile,
            items: items,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: range.count,
            skipCount: range.lowerBound,
            concurrency: concurrency,
            allowsRemoteFetch: allowsRemoteFetch
        )
    }

    private func handleVisibleComicIDsChanged(_ visibleIDs: Set<String>) {
        if visibilityTracker.replaceVisibleIDs(visibleIDs) {
            scheduleThumbnailPreheat()
        }
    }

    private var displayedDirectories: [RemoteDirectoryItem] {
        displaySnapshot.directories
    }

    private var displayedComicFiles: [RemoteDirectoryItem] {
        displaySnapshot.comicFiles
    }

    private var visibleOfflineComicFiles: [RemoteDirectoryItem] {
        displayedComicFiles.filter { viewModel.cacheAvailability(for: $0).hasLocalCopy }
    }

    private var hasVisibleItems: Bool {
        !displayedDirectories.isEmpty || !displayedComicFiles.isEmpty
    }

    private var isPreparingBrowserSnapshot: Bool {
        (isDisplaySnapshotRefreshing || isSectionBuildRefreshing) && !viewModel.items.isEmpty
    }

    private var emptyFolderDescription: String {
        "No folders or supported comics in this location."
    }

    private func browserUnavailableContent(
        title: String,
        systemImage: String,
        description: String
    ) -> some View {
        EmptyStateView(
            systemImage: systemImage,
            title: title,
            description: description
        )
        .padding(.vertical, Spacing.xl)
    }

    private func scheduleDisplaySnapshotRefresh() {
        displaySnapshotRefreshTask?.cancel()
        isDisplaySnapshotRefreshing = true

        let items = viewModel.items
        let sortMode = sortMode

        displaySnapshotRefreshTask = Task.detached(priority: .userInitiated) {
            let nextSnapshot = RemoteBrowserDisplaySnapshot.make(
                from: items,
                sortMode: sortMode
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }

                if nextSnapshot != displaySnapshot {
                    displaySnapshot = nextSnapshot
                }
                displaySnapshotRefreshTask = nil
                isDisplaySnapshotRefreshing = false
            }
        }
    }

    private func scheduleSectionBuild(immediately: Bool = false) {
        sectionBuildDebounceTask?.cancel()
        sectionBuildTask?.cancel()
        isSectionBuildRefreshing = true

        let snapshot = displaySnapshot
        let progressByItemID = viewModel.progressByItemID
        let cacheAvailabilityByItemID = viewModel.cacheAvailabilityByItemID

        let buildSections = {
            sectionBuildTask = Task.detached(priority: .userInitiated) {
                let nextSections = Self.buildUIKitSections(
                    snapshot: snapshot,
                    progressByItemID: progressByItemID,
                    cacheAvailabilityByItemID: cacheAvailabilityByItemID
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard !Task.isCancelled else {
                        return
                    }

                    if nextSections != renderedSections {
                        renderedSections = nextSections
                    }
                    sectionBuildTask = nil
                    isSectionBuildRefreshing = false
                }
            }
        }

        if immediately {
            buildSections()
            return
        }

        sectionBuildDebounceTask = Task(priority: .userInitiated) {
            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard !Task.isCancelled else {
                    return
                }

                buildSections()
                sectionBuildDebounceTask = nil
            }
        }
    }

    private func performImport(
        _ request: RemoteBrowserImportRequest,
        destinationSelection: LibraryImportDestinationSelection,
        scope: RemoteDirectoryImportScope,
        visibleComicSnapshot: [RemoteDirectoryItem],
        cancellationController: RemoteImportCancellationController
    ) async {
        switch request {
        case .currentFolder:
            if scope == .visibleResults {
                await viewModel.importVisibleComics(
                    visibleComicSnapshot,
                    destinationSelection: destinationSelection,
                    cancellationController: cancellationController
                )
            } else {
                await viewModel.importCurrentFolder(
                    destinationSelection: destinationSelection,
                    scope: scope,
                    cancellationController: cancellationController
                )
            }
        case .directory(let item):
            await viewModel.importDirectory(
                item,
                destinationSelection: destinationSelection,
                scope: scope,
                cancellationController: cancellationController
            )
        case .comic(let item):
            await viewModel.importComic(
                item,
                destinationSelection: destinationSelection,
                cancellationController: cancellationController
            )
        }
    }

    nonisolated private static func buildUIKitSections(
        snapshot: RemoteBrowserDisplaySnapshot,
        progressByItemID: [String: RemoteComicReadingSession],
        cacheAvailabilityByItemID: [String: RemoteComicCachedAvailability]
    ) -> [RemoteBrowserListSectionModel] {
        var sections: [RemoteBrowserListSectionModel] = []

        if !snapshot.directories.isEmpty {
            sections.append(
                RemoteBrowserListSectionModel(
                    kind: .directories,
                    title: "Folders",
                    metadataText: Self.metadataText(
                        forCount: snapshot.directories.count,
                        singular: "folder",
                        plural: "folders"
                    ),
                    footerText: nil,
                    items: snapshot.directories.map {
                        RemoteBrowserListRowModel(
                            item: $0,
                            readingSession: nil,
                            cacheAvailability: Self.unavailableCacheAvailability
                        )
                    }
                )
            )
        }

        if !snapshot.comicFiles.isEmpty {
            let downloadedCopies = snapshot.comicFiles.reduce(into: 0) { count, item in
                let itemID = Self.itemIdentifier(for: item)
                if cacheAvailabilityByItemID[itemID]?.kind != .unavailable {
                    count += 1
                }
            }

            let comicMetadata = [
                Self.metadataText(
                    forCount: snapshot.comicFiles.count,
                    singular: "comic",
                    plural: "comics"
                ),
                downloadedCopies > 0
                    ? Self.metadataText(
                        forCount: downloadedCopies,
                        singular: "downloaded copy",
                        plural: "downloaded copies"
                    )
                    : nil
            ]
                .compactMap { $0 }
                .joined(separator: " · ")

            sections.append(
                RemoteBrowserListSectionModel(
                    kind: .comics,
                    title: "Comics",
                    metadataText: comicMetadata.isEmpty ? nil : comicMetadata,
                    footerText: nil,
                    items: snapshot.comicFiles.map {
                        let itemID = Self.itemIdentifier(for: $0)
                        return RemoteBrowserListRowModel(
                            item: $0,
                            readingSession: progressByItemID[itemID],
                            cacheAvailability: cacheAvailabilityByItemID[itemID] ?? Self.unavailableCacheAvailability
                        )
                    }
                )
            )
        }

        if snapshot.unsupportedFileCount > 0 {
            sections.append(
                RemoteBrowserListSectionModel(
                    kind: .notice,
                    title: "",
                    metadataText: nil,
                    footerText: snapshot.unsupportedFileCount == 1
                        ? "1 unsupported file hidden."
                        : "\(snapshot.unsupportedFileCount) unsupported files hidden.",
                    items: []
                )
            )
        }

        return sections
    }

    nonisolated private static var unavailableCacheAvailability: RemoteComicCachedAvailability {
        RemoteComicCachedAvailability(kind: .unavailable)
    }

    nonisolated private static func itemIdentifier(for item: RemoteDirectoryItem) -> String {
        "\(item.serverID.uuidString)|\(item.providerKind.rawValue)|\(item.shareName)|\(item.cacheScopeKey)|\(item.path)"
    }

    nonisolated private static func metadataText(
        forCount count: Int,
        singular: String,
        plural: String
    ) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private func startImportTask(
        _ request: RemoteBrowserImportRequest,
        destinationSelection: LibraryImportDestinationSelection,
        scope: RemoteDirectoryImportScope
    ) {
        let visibleComicSnapshot = displayedComicFiles
        let didStart = dependencies.remoteBackgroundImportController.start { _, cancellationController in
            await performImport(
                request,
                destinationSelection: destinationSelection,
                scope: scope,
                visibleComicSnapshot: visibleComicSnapshot,
                cancellationController: cancellationController
            )
        }

        guard !didStart else {
            return
        }

        viewModel.alert = AppAlertState(
            title: "Import Already Running",
            message: "Another remote import is already running in the app. Wait for it to finish or cancel it from the import banner."
        )
    }

    private func openPrimaryAction(for item: RemoteDirectoryItem) {
        if item.isDirectory {
            navigationRequest = .directory(item.path)
        } else if item.canOpenAsComic {
            presentedComicItem = RemoteComicOpenItem(item: item, mode: .automatic)
        }
    }

    private func openRecoverySession(
        _ session: RemoteComicReadingSession,
        fallbackFrame: CGRect
    ) {
        let item = matchingBrowserItem(for: session) ?? session.directoryItem
        prepareHeroTransition(for: item, fallbackFrame: fallbackFrame)
        presentedComicItem = RemoteComicOpenItem(
            item: item,
            mode: .automatic,
            referenceOverride: session.resolvedComicFileReference(for: viewModel.profile)
        )
    }

    private func openOfflineCopy(for item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        prepareHeroTransition(for: item, fallbackFrame: .zero)
        presentedComicItem = RemoteComicOpenItem(item: item, mode: .preferLocalCache)
    }

    @MainActor
    private func prepareHeroTransition(for item: RemoteDirectoryItem, fallbackFrame: CGRect) {
        lastDismissRefreshItem = item
        let registeredFrame = HeroSourceRegistry.shared.frame(for: item.id)
        heroSourceFrame = registeredFrame == .zero ? fallbackFrame : registeredFrame
        heroPreviewImage = RemoteComicThumbnailPipeline.shared.cachedTransitionImage(
            for: item,
            browsingService: dependencies.remoteServerBrowsingService
        )
    }

    private func matchingBrowserItem(for session: RemoteComicReadingSession) -> RemoteDirectoryItem? {
        viewModel.items.first { item in
            item.serverID == session.serverID
                && item.providerKind == session.providerKind
                && item.shareName == session.shareName
                && item.path == session.path
                && item.comicReferenceKind == session.contentKind
        }
    }

    private func browserInfoSheet(for item: RemoteDirectoryItem) -> some View {
        RemoteComicInfoSheet(
            profile: viewModel.profile,
            item: item,
            readingSession: viewModel.progress(for: item),
            cacheAvailability: viewModel.cacheAvailability(for: item),
            browsingService: dependencies.remoteServerBrowsingService
        )
    }

    private func presentInfoSheet(for item: RemoteDirectoryItem) {
        // Let the UIKit context menu dismissal finish before presenting SwiftUI sheet content.
        DispatchQueue.main.async {
            presentedInfoItem = item
        }
    }

    private func openOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic, availability.hasLocalCopy else {
            return nil
        }

        return {
            openOfflineCopy(for: item)
        }
    }

    private func saveOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic else {
            return nil
        }

        return {
            Task<Void, Never> {
                await viewModel.saveComicForOffline(
                    item,
                    forceRefresh: availability.kind != .unavailable
                )
            }
        }
    }

    private func removeOfflineAction(
        for item: RemoteDirectoryItem,
        availability: RemoteComicCachedAvailability
    ) -> (() -> Void)? {
        guard item.canOpenAsComic, availability.hasLocalCopy else {
            return nil
        }

        return {
            viewModel.removeOfflineCopy(for: item)
        }
    }

    private func importAction(for item: RemoteDirectoryItem) -> (() -> Void)? {
        if item.isDirectory {
            return {
                importRequest = .directory(item)
            }
        }

        guard item.canOpenAsComic else {
            return nil
        }

        return {
            importRequest = .comic(item)
        }
    }

    private var supportsVisibleResultsImportScope: Bool {
        false
    }

    private var saveVisibleComicsButtonTitle: String {
        "Save Visible Comics"
    }

    private var removeVisibleOfflineCopiesButtonTitle: String {
        "Remove Downloaded Copies"
    }

    private var importCurrentFolderButtonTitle: String {
        supportsVisibleResultsImportScope ? "Import Results" : "Import This Folder"
    }

    private func availableImportScopes(for request: RemoteBrowserImportRequest) -> [RemoteDirectoryImportScope] {
        switch request {
        case .currentFolder:
            if supportsVisibleResultsImportScope {
                return [.visibleResults, .currentFolderOnly, .includeSubfolders]
            }
            return [.currentFolderOnly, .includeSubfolders]
        case .directory:
            return [.currentFolderOnly, .includeSubfolders]
        case .comic:
            return [.currentFolderOnly]
        }
    }

    private func defaultImportScope(for request: RemoteBrowserImportRequest) -> RemoteDirectoryImportScope {
        switch request {
        case .currentFolder:
            return supportsVisibleResultsImportScope ? .visibleResults : .includeSubfolders
        case .directory:
            return .includeSubfolders
        case .comic:
            return .currentFolderOnly
        }
    }

    private func applyDisplayMode(_ mode: LibraryComicDisplayMode) {
        displayMode = mode
        dependencies.remoteBrowserPreferencesStore.saveDisplayMode(
            mode,
            for: viewModel.profile.id
        )
    }

    private func applySortMode(_ mode: RemoteDirectorySortMode) {
        sortMode = mode
        dependencies.remoteBrowserPreferencesStore.saveSortMode(
            mode,
            for: viewModel.profile.id
        )
    }

    private func handleAppAlertAction(_ action: AppAlertAction) {
        switch action {
        case .openLibrary(let libraryID, let folderID):
            AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
        }
    }

    private func browserLayoutContext(for containerWidth: CGFloat) -> RemoteServerBrowserLayoutContext {
        RemoteServerBrowserLayoutContext(
            containerWidth: containerWidth,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private func presentVisibleOfflineRemovalConfirmation() {
        let items = visibleOfflineComicFiles
        guard !items.isEmpty else {
            return
        }

        let noun = items.count == 1 ? "visible comic" : "visible comics"

        pendingOfflineRemoval = PendingRemoteOfflineRemoval(
            items: items,
            title: removeVisibleOfflineCopiesButtonTitle,
            buttonTitle: removeVisibleOfflineCopiesButtonTitle,
            message: "Only the downloaded copies of the current \(noun) will be removed from this device. The remote server, saved folder, and reading progress stay intact."
        )
    }

    private func scheduleFeedbackDismissalIfNeeded() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil

        guard let feedback = viewModel.feedback,
              let autoDismissAfter = feedback.autoDismissAfter
        else {
            return
        }

        feedbackDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                guard !Task.isCancelled else {
                    return
                }

                if viewModel.feedback?.id == feedback.id {
                    viewModel.dismissFeedback()
                }
            } catch {
                // Ignore cancellation.
            }
        }
    }
}

struct RemoteBrowserHeaderActionChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(AppFont.caption(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(AppFont.caption(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Color.surfaceSecondary,
            in: RoundedRectangle(cornerRadius: CornerRadius.sm * 2, style: .continuous)
        )
    }
}

struct ThumbnailPreheatPlan {
    let primaryRange: Range<Int>
    let secondaryRanges: [Range<Int>]
}

func makeRemoteAlert(
    for alert: AppAlertState,
    onPrimaryAction: @escaping (AppAlertAction) -> Void = { _ in }
) -> Alert {
    if let primaryAction = alert.primaryAction {
        return Alert(
            title: Text(alert.title),
            message: Text(alert.message),
            primaryButton: .default(Text(primaryAction.title)) {
                onPrimaryAction(primaryAction)
            },
            secondaryButton: .cancel(Text("Not Now"))
        )
    }

    return Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
    )
}

enum RemoteBrowserImportRequest: Identifiable {
    case currentFolder
    case directory(RemoteDirectoryItem)
    case comic(RemoteDirectoryItem)

    var id: String {
        switch self {
        case .currentFolder:
            return "currentFolder"
        case .directory(let item):
            return "directory:\(item.id)"
        case .comic(let item):
            return "comic:\(item.id)"
        }
    }

    var destinationPickerTitle: String {
        switch self {
        case .currentFolder:
            return "Import Folder"
        case .directory:
            return "Import Directory"
        case .comic:
            return "Import Comic"
        }
    }

    var destinationPickerMessage: String {
        switch self {
        case .currentFolder:
            return "Choose where to copy comics from this folder."
        case .directory(let item):
            return "Choose where to copy comics from \(item.name)."
        case .comic(let item):
            return "Choose where to copy \(item.name)."
        }
    }
}

enum RemoteBrowserNavigationRequest: Identifiable, Hashable {
    case directory(String)
    case comic(RemoteDirectoryItem, RemoteComicOpenMode)

    var id: String {
        switch self {
        case .directory(let path):
            return "directory:\(path)"
        case .comic(let item, let openMode):
            switch openMode {
            case .automatic:
                return "comic:\(item.id):automatic"
            case .preferLocalCache:
                return "comic:\(item.id):offline"
            }
        }
    }
}

struct PendingRemoteOfflineRemoval {
    let items: [RemoteDirectoryItem]
    let title: String
    let buttonTitle: String
    let message: String
}

struct RemoteComicOpenItem: Identifiable {
    let id: String
    let item: RemoteDirectoryItem
    let mode: RemoteComicOpenMode
    let referenceOverride: RemoteComicFileReference?

    init(
        item: RemoteDirectoryItem,
        mode: RemoteComicOpenMode,
        referenceOverride: RemoteComicFileReference? = nil
    ) {
        self.item = item
        self.mode = mode
        self.referenceOverride = referenceOverride
        let referenceID = referenceOverride?.id ?? item.id
        self.id = "\(referenceID):\(mode == .automatic ? "auto" : "offline")"
    }
}

struct RemoteBrowserItemActionMenuContent: View {
    let item: RemoteDirectoryItem
    let cacheAvailability: RemoteComicCachedAvailability
    let onShowInfo: (() -> Void)?
    let onOpenOffline: (() -> Void)?
    let onSaveOffline: (() -> Void)?
    let onRemoveOffline: (() -> Void)?
    let onImport: (() -> Void)?

    var body: some View {
        if let onShowInfo {
            Section("Info") {
                Button(action: onShowInfo) {
                    Label("Show File Info", systemImage: "info.circle")
                }
            }
        }

        if onOpenOffline != nil || onSaveOffline != nil || onRemoveOffline != nil {
            Section("Offline") {
                if let onOpenOffline {
                    Button(action: onOpenOffline) {
                        Label(
                            cacheAvailability.kind == .stale ? "Open Older Downloaded Copy" : "Open Downloaded Copy",
                            systemImage: "arrow.down.circle"
                        )
                    }
                }

                if let onSaveOffline {
                    Button(action: onSaveOffline) {
                        Label(saveOfflineTitle, systemImage: saveOfflineSystemImage)
                    }
                }

                if let onRemoveOffline {
                    Button(role: .destructive, action: onRemoveOffline) {
                        Label("Remove Downloaded Copy", systemImage: "trash")
                    }
                }
            }
        }

        if let onImport {
            Section("Library") {
                Button(action: onImport) {
                    Label(
                        item.isDirectory ? "Import Folder to Library" : "Import to Library",
                        systemImage: "square.and.arrow.down.on.square"
                    )
                }
            }
        }
    }

    private var saveOfflineTitle: String {
        switch cacheAvailability.kind {
        case .unavailable:
            return "Save for Offline"
        case .current:
            return "Refresh Downloaded Copy"
        case .stale:
            return "Update Downloaded Copy"
        }
    }

    private var saveOfflineSystemImage: String {
        switch cacheAvailability.kind {
        case .unavailable:
            return "icloud.and.arrow.down"
        case .current, .stale:
            return "arrow.clockwise.icloud"
        }
    }
}
@MainActor
final class RemoteComicVisibilityTracker: ObservableObject {
    private(set) var visibleIDs: Set<String> = []

    func markVisible(_ id: String) -> Bool {
        let previousCount = visibleIDs.count
        visibleIDs.insert(id)
        return visibleIDs.count != previousCount
    }

    func markInvisible(_ id: String) -> Bool {
        visibleIDs.remove(id) != nil
    }

    func reset() {
        visibleIDs.removeAll()
    }

    func replaceVisibleIDs(_ ids: Set<String>) -> Bool {
        guard visibleIDs != ids else {
            return false
        }

        visibleIDs = ids
        return true
    }
}

struct RemoteBrowserDisplaySnapshot: Equatable {
    let directories: [RemoteDirectoryItem]
    let comicFiles: [RemoteDirectoryItem]
    let unsupportedFileCount: Int

    static let empty = RemoteBrowserDisplaySnapshot(
        directories: [],
        comicFiles: [],
        unsupportedFileCount: 0
    )

    nonisolated static func make(
        from items: [RemoteDirectoryItem],
        sortMode: RemoteDirectorySortMode
    ) -> RemoteBrowserDisplaySnapshot {
        return RemoteBrowserDisplaySnapshot(
            directories: sortItems(
                items.filter { $0.kind == .directory },
                using: sortMode
            ),
            comicFiles: sortItems(
                items.filter { $0.canOpenAsComic },
                using: sortMode
            ),
            unsupportedFileCount: items.reduce(into: 0) { count, item in
                if item.kind == .unsupportedFile {
                    count += 1
                }
            }
        )
    }

    nonisolated private static func sortItems(
        _ items: [RemoteDirectoryItem],
        using mode: RemoteDirectorySortMode
    ) -> [RemoteDirectoryItem] {
        items.sorted { lhs, rhs in
            switch mode {
            case .nameAscending:
                return compareByName(lhs, rhs) < 0
            case .recentlyUpdated:
                return compareOptional(
                    lhs.modifiedAt,
                    rhs.modifiedAt,
                    fallback: { compareByName(lhs, rhs) }
                ) < 0
            case .largestFirst:
                return compareOptional(
                    lhs.fileSize,
                    rhs.fileSize,
                    fallback: { compareByName(lhs, rhs) }
                ) < 0
            }
        }
    }

    nonisolated private static func compareByName(
        _ lhs: RemoteDirectoryItem,
        _ rhs: RemoteDirectoryItem
    ) -> Int {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending:
            return -1
        case .orderedDescending:
            return 1
        case .orderedSame:
            return 0
        }
    }

    nonisolated private static func compareOptional<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        fallback: () -> Int
    ) -> Int {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs ? -1 : 1
        case (_?, nil):
            return -1
        case (nil, _?):
            return 1
        default:
            return fallback()
        }
    }
}
