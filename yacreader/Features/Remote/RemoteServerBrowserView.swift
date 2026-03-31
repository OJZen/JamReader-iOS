import Combine
import SwiftUI
import UIKit

struct RemoteServerBrowserView: View {
    private enum LayoutMetrics {
        static let horizontalInset: CGFloat = 12
        static let rowAccessoryReservedWidth: CGFloat = 36
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerBrowserViewModel
    @State private var displayMode: LibraryComicDisplayMode = .list
    @State private var hasConfiguredDisplayMode = false
    @State private var sortMode: RemoteDirectorySortMode = .nameAscending
    @State private var hasConfiguredSortMode = false
    @State private var searchText = ""
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

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
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
        browserContent
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { browserToolbar }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: thumbnailPreheatRequestID) {
            await preheatVisibleThumbnails()
        }
        .onAppear {
            viewModel.refreshProgressState()
            viewModel.refreshShortcutState()
            configureDisplayModeIfNeeded()
            configureSortModeIfNeeded()
            refreshDisplaySnapshot()
        }
        .onChange(of: viewModel.items) { _, _ in
            refreshDisplaySnapshot()
        }
        .onChange(of: searchText) { _, _ in
            refreshDisplaySnapshot()
        }
        .onChange(of: sortMode) { _, _ in
            refreshDisplaySnapshot()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.feedback?.id) { _, _ in
            scheduleFeedbackDismissalIfNeeded()
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
            visibilityTracker.reset()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Filter this folder"
        )
        .safeAreaInset(edge: .bottom) {
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
                                handleRemoteAlertPrimaryAction(action)
                            }
                        },
                        onDismiss: {
                            viewModel.dismissFeedback()
                        }
                    )
                }
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert, onPrimaryAction: handleRemoteAlertPrimaryAction(_:))
        }
        .confirmationDialog(
            pendingOfflineRemoval?.title ?? "Remove downloaded copies?",
            isPresented: Binding(
                get: { pendingOfflineRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingOfflineRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingOfflineRemoval {
                Button(pendingOfflineRemoval.buttonTitle, role: .destructive) {
                    viewModel.removeOfflineCopies(for: pendingOfflineRemoval.items)
                    self.pendingOfflineRemoval = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingOfflineRemoval = nil
            }
        } message: {
            if let pendingOfflineRemoval {
                Text(pendingOfflineRemoval.message)
            }
        }
        .sheet(item: $importRequest, content: importSheet)
        .navigationDestination(item: $navigationRequest, destination: navigationDestination)
        .background(readerPresenter)
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
                openMode: open.mode
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
                    Section(trimmedSearchText.isEmpty ? "Folder" : "Results") {
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
                dependencies: dependencies
            )
        case .comic:
            EmptyView() // Comics are now presented via fullScreenCover
        }
    }

    private var listBody: some View {
        List {
            summarySection
            listContentSections
        }
        .scrollContentBackground(.hidden)
        .background(Color.surfaceGrouped)
    }

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                summaryCard
                gridContentSections
            }
            .padding(.horizontal, LayoutMetrics.horizontalInset)
            .padding(.vertical, Spacing.lg)
            .adaptiveContentWidth(1120)
        }
        .background(Color.surfaceGrouped)
    }

    private var summarySection: some View {
        Section {
            summaryCard
                .insetCardListRow(
                    horizontalInset: LayoutMetrics.horizontalInset,
                    top: 14,
                    bottom: 10
                )
        }
    }

    private var summaryCard: some View {
        InsetCard(
            cornerRadius: 18,
            contentPadding: 12,
            backgroundColor: Color.surfacePrimary,
            strokeOpacity: 0.04
        ) {
            summaryContent
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(viewModel.currentPathDisplayText)
                    .font(AppFont.subheadline(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: isRootFolder ? "square.grid.2x2.fill" : "folder.fill")
                    .font(AppFont.caption(.semibold))
                    .foregroundStyle(isRootFolder ? .teal : .blue)
            }

            SummaryMetricGroup(
                metrics: summaryMetrics,
                style: .compactValue,
                horizontalSpacing: Spacing.sm,
                verticalSpacing: Spacing.xs
            )

            RemoteInlineMetadataLine(
                items: summaryMetadataItems,
                horizontalSpacing: Spacing.xs,
                verticalSpacing: Spacing.xxs
            )

            Label(summaryDescription, systemImage: "folder")
                .font(AppFont.footnote(.medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private var listContentSections: some View {
        if viewModel.isLoading {
            Section {
                LoadingStateView(message: "Connecting to Remote Library")
                    .padding(.vertical, Spacing.lg)
            }
        } else if viewModel.loadIssue != nil {
            Section {
                remoteErrorContent()
            }
        } else if viewModel.items.isEmpty {
            Section {
                browserUnavailableContent(
                    title: "No Remote Files",
                    systemImage: "folder",
                    description: emptyFolderDescription
                )
            }
        } else if !hasVisibleItems {
            Section {
                browserUnavailableContent(
                    title: "No Matches",
                    systemImage: "magnifyingglass",
                    description: noMatchesDescription
                )
            }
        } else {
            if !displayedDirectories.isEmpty {
                Section {
                    ForEach(displayedDirectories) { item in
                        Button {
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteInsetListRowCard {
                                RemoteDirectoryItemListRow(
                                    item: item,
                                    readingSession: nil,
                                    cacheAvailability: .unavailable,
                                    profile: viewModel.profile,
                                    browsingService: dependencies.remoteServerBrowsingService,
                                    trailingAccessoryReservedWidth: itemAccessoryReservedWidth
                                )
                                .equatable()
                            }
                        }
                        .buttonStyle(.plain)
                        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                        .overlay(alignment: .trailing) {
                            if showsPersistentItemActions {
                                browserItemActionMenu(for: item)
                                    .padding(.trailing, 8)
                            }
                        }
                        .contextMenu {
                            browserItemActionMenuContent(for: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            browserItemSwipeActions(for: item)
                        }
                    }
                } header: {
                    contentSectionHeader(
                        title: folderSectionTitle,
                        metadataItems: folderSectionMetadataItems
                    )
                }
            }

            if !displayedComicFiles.isEmpty {
                Section {
                    ForEach(displayedComicFiles) { item in
                        let availability = viewModel.cacheAvailability(for: item)

                        HeroTapButton { frame in
                            prepareHeroTransition(for: item, fallbackFrame: frame)
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteInsetListRowCard {
                                RemoteDirectoryItemListRow(
                                    item: item,
                                    readingSession: viewModel.progress(for: item),
                                    cacheAvailability: availability,
                                    profile: viewModel.profile,
                                    browsingService: dependencies.remoteServerBrowsingService,
                                    heroSourceID: item.id,
                                    trailingAccessoryReservedWidth: itemAccessoryReservedWidth
                                )
                                .equatable()
                            }
                        }
                        .onAppear {
                            markComicVisible(item)
                        }
                        .onDisappear {
                            markComicInvisible(item)
                        }
                        .buttonStyle(.plain)
                        .insetCardListRow(horizontalInset: LayoutMetrics.horizontalInset)
                        .overlay(alignment: .trailing) {
                            if showsPersistentItemActions {
                                browserItemActionMenu(for: item)
                                    .padding(.trailing, 8)
                            }
                        }
                        .contextMenu {
                            browserItemActionMenuContent(for: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            browserItemSwipeActions(for: item)
                        }
                    }
                } header: {
                    contentSectionHeader(
                        title: comicSectionTitle,
                        metadataItems: comicSectionMetadataItems
                    )
                } footer: {
                    if let unsupportedFilesNoticeText {
                        Text(unsupportedFilesNoticeText)
                    }
                }
            }
        }
    }

    private var isRootFolder: Bool {
        viewModel.currentPath == viewModel.rootPath
    }

    private var showsPersistentItemActions: Bool {
        horizontalSizeClass == .regular
    }

    private var itemAccessoryReservedWidth: CGFloat {
        showsPersistentItemActions ? LayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var summaryMetrics: [SummaryMetricItem] {
        [
            SummaryMetricItem(
                title: "Folders",
                value: "\(displayedDirectories.count)",
                tint: .blue
            ),
            SummaryMetricItem(
                title: "Comics",
                value: "\(displayedComicFiles.count)",
                tint: .green
            ),
            SummaryMetricItem(
                title: "Offline",
                value: "\(visibleOfflineComicFiles.count)",
                tint: .orange
            )
        ]
    }

    private var summaryMetadataItems: [RemoteInlineMetadataItem] {
        var items = [
            RemoteInlineMetadataItem(
                systemImage: "server.rack",
                text: viewModel.profile.name,
                tint: .secondary
            )
        ]

        if viewModel.isCurrentFolderSaved {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "star.fill",
                    text: "Saved folder",
                    tint: .yellow
                )
            )
        }

        if !trimmedSearchText.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "magnifyingglass",
                    text: "Filtering",
                    tint: .orange
                )
            )
        }

        if displayedUnsupportedFileCount > 0 && trimmedSearchText.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "eye.slash",
                    text: displayedUnsupportedFileCount == 1 ? "1 hidden" : "\(displayedUnsupportedFileCount) hidden",
                    tint: .secondary
                )
            )
        }

        return items
    }

    private var summaryDescription: String {
        if !trimmedSearchText.isEmpty {
            return hasVisibleItems
                ? "Showing filtered results inside this folder."
                : "No folders or comics match the current filter."
        }

        if isRootFolder {
            return "Browse folders and open comics from this remote location."
        }

        return "Browse folders and comics inside the current remote path."
    }

    @ViewBuilder
    private var gridContentSections: some View {
        if viewModel.isLoading {
            LoadingStateView(message: "Connecting to Remote Library")
                .padding(.vertical, Spacing.lg)
        } else if viewModel.loadIssue != nil {
            remoteErrorContent()
                .frame(maxWidth: .infinity)
        } else if viewModel.items.isEmpty {
            browserUnavailableContent(
                title: "No Remote Files",
                systemImage: "folder",
                description: emptyFolderDescription
            )
        } else if !hasVisibleItems {
            browserUnavailableContent(
                title: "No Matches",
                systemImage: "magnifyingglass",
                description: noMatchesDescription
            )
        } else {
            if !displayedDirectories.isEmpty {
                remoteGridSection(
                    title: folderSectionTitle,
                    metadataItems: folderSectionMetadataItems,
                    items: displayedDirectories
                )
            }

            if !displayedComicFiles.isEmpty {
                remoteGridSection(
                    title: comicSectionTitle,
                    metadataItems: comicSectionMetadataItems,
                    items: displayedComicFiles
                )

                if displayedUnsupportedFileCount > 0 {
                    unsupportedFilesNoticeView
                }
            }
        }
    }

    private func remoteGridSection(
        title: String,
        metadataItems: [RemoteInlineMetadataItem],
        items: [RemoteDirectoryItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            contentSectionHeader(title: title, metadataItems: metadataItems)

            LazyVGrid(
                columns: [GridItem(.adaptive(
                    minimum: horizontalSizeClass == .regular ? 200 : 156,
                    maximum: horizontalSizeClass == .regular ? 280 : 206
                ), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                ForEach(items) { item in
                    let availability = viewModel.cacheAvailability(for: item)

                    ZStack(alignment: .topTrailing) {
                        HeroTapButton { frame in
                            prepareHeroTransition(for: item, fallbackFrame: frame)
                            openPrimaryAction(for: item)
                        } label: {
                            RemoteDirectoryGridCard(
                                item: item,
                                readingSession: viewModel.progress(for: item),
                                cacheAvailability: availability,
                                profile: viewModel.profile,
                                browsingService: dependencies.remoteServerBrowsingService,
                                heroSourceID: item.id
                            )
                            .equatable()
                        }
                        .onAppear {
                            markComicVisible(item)
                        }
                        .onDisappear {
                            markComicInvisible(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            browserItemActionMenuContent(for: item)
                        }

                        if showsPersistentItemActions {
                            browserItemActionMenu(for: item)
                                .padding(12)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentSectionHeader(
        title: String,
        metadataItems: [RemoteInlineMetadataItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(AppFont.headline())

            RemoteInlineMetadataLine(
                items: metadataItems,
                horizontalSpacing: Spacing.xs,
                verticalSpacing: Spacing.xxs
            )
        }
        .textCase(nil)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let recoverySuggestion = loadIssue?.recoverySuggestion {
                Label(recoverySuggestion, systemImage: "lightbulb")
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    retryButton
                    manageServersButton(loadIssue: loadIssue)
                    continueReadingButton
                    offlineShelfButton
                }
            }

            if loadIssue?.prefersPathRecoveryActions == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        upOneLevelButton
                        sessionRootButton
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        upOneLevelButton
                        sessionRootButton
                    }
                }
            }
        }
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
                prepareHeroTransition(for: recoverySession.directoryItem, fallbackFrame: frame)
                openPrimaryAction(for: recoverySession.directoryItem)
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

    private var folderSectionTitle: String {
        trimmedSearchText.isEmpty ? "Folders" : "Matching Folders"
    }

    private var comicSectionTitle: String {
        trimmedSearchText.isEmpty ? "Comic Files" : "Matching Comics"
    }

    private var folderSectionMetadataItems: [RemoteInlineMetadataItem] {
        [
            RemoteInlineMetadataItem(
                systemImage: "folder.fill",
                text: displayedDirectories.count == 1 ? "1 folder" : "\(displayedDirectories.count) folders",
                tint: .blue
            )
        ]
    }

    private var comicSectionMetadataItems: [RemoteInlineMetadataItem] {
        var items = [
            RemoteInlineMetadataItem(
                systemImage: "book.closed.fill",
                text: displayedComicFiles.count == 1 ? "1 comic" : "\(displayedComicFiles.count) comics",
                tint: .green
            )
        ]

        if !visibleOfflineComicFiles.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "arrow.down.circle.fill",
                    text: visibleOfflineComicFiles.count == 1 ? "1 downloaded copy" : "\(visibleOfflineComicFiles.count) downloaded copies",
                    tint: .orange
                )
            )
        }

        return items
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
            defaultMode: horizontalSizeClass == .regular ? .grid : .list
        )
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

    private var thumbnailPreheatRequestID: String {
        let plan = thumbnailPreheatPlan
        return "\(viewModel.profile.id.uuidString)#\(displayMode.rawValue)#\(sortMode.rawValue)#\(trimmedSearchText)#\(Int(displayScale * 100))#\(plan.requestSignature)"
    }

    private func preheatVisibleThumbnails() async {
        guard !viewModel.isLoading, !displayedComicFiles.isEmpty else {
            return
        }

        let maxDimension: CGFloat = displayMode == .grid ? 208 : 76
        let maxPixelSize = Int(maxDimension * max(displayScale, 1))
        let plan = thumbnailPreheatPlan

        await preheatThumbnails(
            in: plan.primaryRange,
            maxPixelSize: maxPixelSize,
            concurrency: displayMode == .grid ? 3 : 2,
            allowsRemoteFetch: true
        )

        guard !Task.isCancelled else {
            return
        }

        for secondaryRange in plan.secondaryRanges {
            await preheatThumbnails(
                in: secondaryRange,
                maxPixelSize: maxPixelSize,
                concurrency: 2,
                allowsRemoteFetch: false
            )

            guard !Task.isCancelled else {
                return
            }
        }
    }

    private var thumbnailPreheatPlan: ThumbnailPreheatPlan {
        let items = displayedComicFiles
        guard !items.isEmpty else {
            return ThumbnailPreheatPlan(
                primaryRange: 0..<0,
                secondaryRanges: [],
                requestSignature: "empty"
            )
        }

        let visibleIndexes = items.enumerated().compactMap { index, item in
            visibilityTracker.visibleIDs.contains(item.id) ? index : nil
        }

        let defaultVisibleUpperBound = min(
            items.count - 1,
            displayMode == .grid ? 5 : 2
        )
        let visibleLowerBound = visibleIndexes.min() ?? 0
        let visibleUpperBound = visibleIndexes.max() ?? defaultVisibleUpperBound

        let primaryLeadingPadding = displayMode == .grid ? 18 : 8
        let primaryTrailingPadding = displayMode == .grid ? 6 : 2
        let secondaryLeadingPadding = displayMode == .grid ? 42 : 18
        let secondaryTrailingPadding = displayMode == .grid ? 12 : 4

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

        let visibleSignature = visibleIndexes.map(String.init).joined(separator: ",")
        let secondarySignature = secondaryRanges
            .map { "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: "|")

        return ThumbnailPreheatPlan(
            primaryRange: primaryRange,
            secondaryRanges: secondaryRanges,
            requestSignature: "\(visibleSignature)#\(primaryRange.lowerBound)-\(primaryRange.upperBound)#\(secondarySignature)"
        )
    }

    private func preheatThumbnails(
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
            items: displayedComicFiles,
            browsingService: dependencies.remoteServerBrowsingService,
            maxPixelSize: maxPixelSize,
            limit: range.count,
            skipCount: range.lowerBound,
            concurrency: concurrency,
            allowsRemoteFetch: allowsRemoteFetch
        )
    }

    private func markComicVisible(_ item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        visibilityTracker.markVisible(item.id)
    }

    private func markComicInvisible(_ item: RemoteDirectoryItem) {
        guard item.canOpenAsComic else {
            return
        }

        visibilityTracker.markInvisible(item.id)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var displayedUnsupportedFileCount: Int {
        displaySnapshot.unsupportedFileCount
    }

    private var hasVisibleItems: Bool {
        !displayedDirectories.isEmpty || !displayedComicFiles.isEmpty
    }

    private var emptyFolderDescription: String {
        if trimmedSearchText.isEmpty {
            return "No folders or supported comics in this location."
        }

        return noMatchesDescription
    }

    private var noMatchesDescription: String {
        "No folders or comics match \"\(trimmedSearchText)\"."
    }

    private var unsupportedFilesNoticeText: String? {
        guard displayedUnsupportedFileCount > 0 else {
            return nil
        }

        return displayedUnsupportedFileCount == 1
            ? "1 unsupported file hidden."
            : "\(displayedUnsupportedFileCount) unsupported files hidden."
    }

    @ViewBuilder
    private var unsupportedFilesNoticeView: some View {
        if let unsupportedFilesNoticeText {
            Text(unsupportedFilesNoticeText)
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
        }
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

    private func refreshDisplaySnapshot() {
        let nextSnapshot = RemoteBrowserDisplaySnapshot.make(
            from: viewModel.items,
            searchText: searchText,
            sortMode: sortMode
        )

        guard nextSnapshot != displaySnapshot else {
            return
        }

        displaySnapshot = nextSnapshot
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

        viewModel.alert = RemoteAlertState(
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

    @ViewBuilder
    private func browserItemActionMenuContent(for item: RemoteDirectoryItem) -> some View {
        let availability = viewModel.cacheAvailability(for: item)

        RemoteBrowserItemActionMenuContent(
            item: item,
            cacheAvailability: availability,
            onOpenOffline: openOfflineAction(for: item, availability: availability),
            onSaveOffline: saveOfflineAction(for: item, availability: availability),
            onRemoveOffline: removeOfflineAction(for: item, availability: availability),
            onImport: importAction(for: item)
        )
    }

    private func browserItemActionMenu(for item: RemoteDirectoryItem) -> some View {
        Menu {
            browserItemActionMenuContent(for: item)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(item.name)")
    }

    @ViewBuilder
    private func browserItemSwipeActions(for item: RemoteDirectoryItem) -> some View {
        let availability = viewModel.cacheAvailability(for: item)

        if let onRemoveOffline = removeOfflineAction(for: item, availability: availability) {
            Button(role: .destructive, action: onRemoveOffline) {
                Label("Remove", systemImage: "trash")
            }
        }

        if let onSaveOffline = saveOfflineAction(for: item, availability: availability),
           item.canOpenAsComic {
            Button(action: onSaveOffline) {
                Label(
                    availability.kind == .unavailable ? "Offline" : "Refresh",
                    systemImage: availability.kind == .unavailable
                        ? "icloud.and.arrow.down"
                        : "arrow.clockwise.icloud"
                )
            }
            .tint(availability.kind == .unavailable ? .blue : .orange)
        } else if let onImport = importAction(for: item), item.isDirectory {
            Button(action: onImport) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .tint(.teal)
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
        !trimmedSearchText.isEmpty && !displayedComicFiles.isEmpty
    }

    private var saveVisibleComicsButtonTitle: String {
        trimmedSearchText.isEmpty ? "Save Visible Comics" : "Save Results Offline"
    }

    private var removeVisibleOfflineCopiesButtonTitle: String {
        trimmedSearchText.isEmpty ? "Remove Downloaded Copies" : "Remove Downloaded Result Copies"
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

    private func handleRemoteAlertPrimaryAction(_ action: RemoteAlertPrimaryAction) {
        switch action {
        case .openLibrary(let libraryID, let folderID):
            AppNavigationRouter.openLibrary(libraryID, folderID: folderID)
        }
    }

    private func presentVisibleOfflineRemovalConfirmation() {
        let items = visibleOfflineComicFiles
        guard !items.isEmpty else {
            return
        }

        let noun: String
        if trimmedSearchText.isEmpty {
            noun = items.count == 1 ? "visible comic" : "visible comics"
        } else {
            noun = items.count == 1 ? "matching result" : "matching results"
        }

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
    let requestSignature: String
}

func makeRemoteAlert(
    for alert: RemoteAlertState,
    onPrimaryAction: @escaping (RemoteAlertPrimaryAction) -> Void = { _ in }
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

    init(item: RemoteDirectoryItem, mode: RemoteComicOpenMode) {
        self.item = item
        self.mode = mode
        self.id = "\(item.id):\(mode == .automatic ? "auto" : "offline")"
    }
}

struct RemoteBrowserItemActionMenuContent: View {
    let item: RemoteDirectoryItem
    let cacheAvailability: RemoteComicCachedAvailability
    let onOpenOffline: (() -> Void)?
    let onSaveOffline: (() -> Void)?
    let onRemoveOffline: (() -> Void)?
    let onImport: (() -> Void)?

    var body: some View {
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
    @Published private(set) var visibleIDs: Set<String> = []

    private var pendingVisibleIDs: Set<String> = []
    private var publishTask: Task<Void, Never>?

    func markVisible(_ id: String) {
        pendingVisibleIDs.insert(id)
        schedulePublish()
    }

    func markInvisible(_ id: String) {
        pendingVisibleIDs.remove(id)
        schedulePublish()
    }

    func reset() {
        publishTask?.cancel()
        publishTask = nil
        pendingVisibleIDs.removeAll()
        visibleIDs.removeAll()
    }

    private func schedulePublish() {
        publishTask?.cancel()

        publishTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else {
                return
            }

            if pendingVisibleIDs != visibleIDs {
                visibleIDs = pendingVisibleIDs
            }
        }
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

    static func make(
        from items: [RemoteDirectoryItem],
        searchText: String,
        sortMode: RemoteDirectorySortMode
    ) -> RemoteBrowserDisplaySnapshot {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems: [RemoteDirectoryItem]

        if trimmedSearchText.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.name.localizedStandardContains(trimmedSearchText)
            }
        }

        return RemoteBrowserDisplaySnapshot(
            directories: filteredItems
                .filter(\.isDirectory)
                .sorted(using: sortMode),
            comicFiles: filteredItems
                .filter(\.canOpenAsComic)
                .sorted(using: sortMode),
            unsupportedFileCount: filteredItems.reduce(into: 0) { count, item in
                if item.kind == .unsupportedFile {
                    count += 1
                }
            }
        )
    }
}
