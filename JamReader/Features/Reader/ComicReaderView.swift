import SwiftUI
import UIKit

struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let dependencies: AppDependencies
    private let openingPreviewImage: UIImage?
    /// The server a remote comic comes from, offered for editing when opening fails.
    private let remoteProfile: RemoteServerProfile?
    private let remoteItem: RemoteDirectoryItem?

    @StateObject private var viewModel: ComicReaderViewModel
    @StateObject private var readerSession: ReaderSessionController
    @State private var isShowingMetadataSheet = false
    @State private var isShowingOrganizationSheet = false
    @State private var isShowingInfoSheet = false
    @State private var isShowingDisplayPanel = false
    @State private var isShowingThumbnailBrowser = false
    @State private var isShowingBookmarkLimitAlert = false
    @State private var readStatusToastMessage: String?
    @State private var isContentZoomed = false
    @State private var isDismissGestureActive = false
    @State private var isPageNavigationInteracting = false
    @State private var keepsScreenAwake: Bool

    @MainActor
    init(
        request: ComicOpenRequest,
        dependencies: AppDependencies,
        openingPreviewImage: UIImage? = nil
    ) {
        self.dependencies = dependencies
        self.openingPreviewImage = openingPreviewImage
        if case .remote(let remoteRequest) = request {
            self.remoteProfile = remoteRequest.profile
            self.remoteItem = remoteRequest.item
        } else {
            self.remoteProfile = nil
            self.remoteItem = nil
        }
        _keepsScreenAwake = State(
            initialValue: dependencies.readerBehaviorPreferencesStore.loadKeepsScreenAwake()
        )
        let initialLayout = dependencies.readerLayoutPreferencesStore.loadLayout()
        let initialDescriptor = ReaderContentDescriptor.placeholder(
            documentURL: request.fallbackDocumentURL,
            pageCount: request.fallbackPageCount,
            initialPageIndex: request.fallbackPageIndex,
            layout: initialLayout
        )
        _viewModel = StateObject(
            wrappedValue: ComicReaderViewModel(
                request: request,
                dependencies: dependencies
            )
        )
        _readerSession = StateObject(
            wrappedValue: ReaderSessionController(descriptor: initialDescriptor)
        )
    }

    var body: some View {
        ReaderSurface(
            isInteractionLocked: readerSession.state.isPageJumpPresented,
            isChromeHidden: !readerSession.state.isChromeVisible || isDismissGestureActive
        ) {
            ZStack {
                if let document = viewModel.document {
                    readerContent(for: document)
                        .zIndex(1)
                } else if viewModel.isLoading || !viewModel.hasAttemptedInitialLoad {
                    ReaderOpeningStateView(
                        previewImage: openingPreviewImage,
                        title: viewModel.navigationTitle,
                        detail: viewModel.loadingMessage,
                        progress: viewModel.loadingProgress,
                        onCancel: cancelOpeningAndDismiss
                    )
                } else {
                    ReaderOpenFailureView(
                        title: viewModel.navigationTitle,
                        message: viewModel.failureMessage
                            ?? String(localized: "The selected comic could not be opened."),
                        onClose: dismiss.callAsFunction,
                        onRetry: viewModel.load,
                        onEditServer: remoteProfile.map { profile in
                            { presentServerEditor(for: profile) }
                        }
                    )
                }
            }
            .background(Color.black.ignoresSafeArea())
            .id(readerRenderIdentity)
        } topBar: {
            readerTopBar
        } bottomBar: { viewportSize in
            readerBottomBar(viewportHeight: viewportSize.height)
        } sideOverlay: { viewportSize, safeAreaInsets in
            readerSideOverlay(
                viewportSize: viewportSize,
                safeAreaInsets: safeAreaInsets
            )
        } statusOverlay: {
            readerStatusOverlay
        } modalOverlay: {
            if readerSession.state.isPageJumpPresented {
                ReaderPageJumpOverlay(
                    pageNumberText: pageJumpTextBinding,
                    currentPageNumber: viewModel.currentPageNumber ?? 1,
                    pageCount: viewModel.pageCount ?? 1,
                    onCancel: { readerSession.apply(.dismissPageJump) },
                    onJump: submitPageJump
                )
            }
        }
        .pullDownToDismiss(
            isEnabled: !readerSession.state.isPageJumpPresented && !isPageNavigationInteracting && !isAnySheetPresented,
            direction: dismissGestureDirection,
            isZoomed: isContentZoomed,
            onDismissGestureActiveChanged: { active in
                isDismissGestureActive = active
            },
            onDismiss: {
                let t = Transaction(animation: .none)
                withTransaction(t) { dismiss() }
            }
        )
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBar(hidden: !readerSession.state.isChromeVisible)
        .background {
            Button("", action: dismiss.callAsFunction)
                .keyboardShortcut("w", modifiers: .command)
                .allowsHitTesting(false)
                .opacity(0)
        }
        .task {
            await Task.yield()
            startInitialLoad()
        }
        .onAppear {
            reloadIdleTimerPreference()
            startInitialLoad()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.persistCurrentProgress()
        }
        .onChange(of: scenePhase) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: supportsDoublePageSpread) { _, _ in
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
            scheduleReaderSessionSynchronization()
        }
        .onChange(of: viewModel.documentIdentity) { _, _ in
            updateIdleTimerState()
            scheduleReaderSessionSynchronization()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .readerBehaviorPreferencesDidChange
            )
        ) { _ in
            reloadIdleTimerPreference()
        }
        .onChange(of: viewModel.readerLayout) { _, _ in
            scheduleReaderSessionSynchronization()
        }
        .onChange(of: dismissGestureDirection) { _, _ in
            isContentZoomed = false
            isDismissGestureActive = false
        }
        .onChange(of: viewModel.currentPageIndex) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }

            DispatchQueue.main.async {
                readerSession.apply(.syncVisiblePage(newValue))
                ReaderGestureCoordinator.hideChrome(session: readerSession)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            // The reader stays dark whatever the system appearance.
            Color.clear
                .allowsHitTesting(false)
                .lightToast(
                    isPresented: Binding(
                        get: { readStatusToastMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                readStatusToastMessage = nil
                            }
                        }
                    ),
                    message: readStatusToastMessage ?? "",
                    systemImage: "checkmark.circle"
                )
                .environment(\.colorScheme, .dark)
        }
    }

    private var supportsDoublePageSpread: Bool {
        horizontalSizeClass == .regular
    }

    private var dismissGestureDirection: ReaderDismissGestureDirection {
        guard usesVerticalContinuousComicLayout else {
            return .down
        }

        return .right
    }

    private var usesVerticalContinuousComicLayout: Bool {
        guard readerSession.state.layout.pagingMode == .verticalContinuous,
              case .imageSequence(let imageSequence) = viewModel.document
        else {
            return false
        }

        return imageSequence.usesComicImageLayout
    }

    private var readerRenderIdentity: String {
        viewModel.documentIdentity ?? "opening-\(viewModel.hasAttemptedInitialLoad)"
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        ReaderDocumentContentView(
            document: document,
            pageIndex: readerSession.state.currentPageIndex,
            layout: readerSession.state.layout,
            isDismissGestureActive: isDismissGestureActive,
            onPageChanged: handleVisiblePageChange(to:),
            onReaderTap: handleReaderTap,
            onZoomStateChanged: { zoomed in
                DispatchQueue.main.async {
                    isContentZoomed = zoomed
                }
            }
        ) { unsupportedDocument in
            ReaderFallbackStateView(
                title: String(localized: "Reader Not Ready"),
                systemImage: "shippingbox",
                message: unsupportedReaderMessage(for: unsupportedDocument)
            )
        }
    }

    private func unsupportedReaderMessage(for unsupportedDocument: UnsupportedComicDocument) -> String {
        unsupportedDocument.reason
    }

    private var isAnySheetPresented: Bool {
        isShowingDisplayPanel || isShowingMetadataSheet ||
        isShowingOrganizationSheet || isShowingInfoSheet ||
        isShowingThumbnailBrowser
    }

    private var supportsBookmarks: Bool {
        viewModel.pageCount != nil
    }

    private var displayPanelControls: ReaderDisplayPanelControls {
        ReaderDisplayPanelControls(
            layout: viewModel.effectiveReaderLayout,
            supportsImageLayoutControls: viewModel.supportsImageLayoutControls,
            supportsDoublePageSpread: viewModel.allowsDoublePageSpread,
            supportsRotation: viewModel.supportsRotationControls
        )
    }

    private var readerTopBar: some View {
        ReaderTopBar(
            title: viewModel.navigationTitle,
            onBack: dismiss.callAsFunction,
            isBookmarked: supportsBookmarks ? viewModel.currentPageIsBookmarked : nil,
            onToggleBookmark: toggleBookmark,
            showsDisplaySettings: !displayPanelControls.isEmpty,
            isDisplayPanelPresented: $isShowingDisplayPanel,
            isToolsDisabled: viewModel.document == nil
        ) {
            readerDisplayPanel
        } moreMenu: {
            readerMoreMenu
        }
        .alert("Up to 3 Bookmarks per Comic", isPresented: $isShowingBookmarkLimitAlert) {
            ForEach(viewModel.bookmarkItems) { bookmark in
                Button("Replace Bookmark on Page \(bookmark.pageNumber)") {
                    viewModel.replaceBookmark(at: bookmark.pageIndex)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pageNumber = viewModel.currentPageNumber {
                Text("Choose one to replace with page \(pageNumber)")
            }
        }
    }

    private var readerDisplayPanel: some View {
        ReaderDisplayPanel(
            layout: viewModel.effectiveReaderLayout,
            controls: displayPanelControls,
            presentsAsPopover: horizontalSizeClass == .regular,
            actions: ReaderDisplayPanelActions(
                setPagingMode: { pagingMode in
                    viewModel.setPagingMode(pagingMode)
                    scheduleReaderSessionSynchronization()
                },
                setSpreadMode: { spreadMode in
                    viewModel.setSpreadMode(spreadMode)
                    scheduleReaderSessionSynchronization()
                },
                setReadingDirection: { readingDirection in
                    viewModel.setReadingDirection(readingDirection)
                    scheduleReaderSessionSynchronization()
                },
                setCoverAsSinglePage: { coverAsSinglePage in
                    viewModel.setCoverAsSinglePage(coverAsSinglePage)
                    scheduleReaderSessionSynchronization()
                },
                setFitMode: { fitMode in
                    viewModel.setFitMode(fitMode)
                    scheduleReaderSessionSynchronization()
                },
                setPageSpacingEnabled: { pageSpacingEnabled in
                    viewModel.setPageSpacingEnabled(pageSpacingEnabled)
                    scheduleReaderSessionSynchronization()
                },
                rotateCounterClockwise: {
                    viewModel.rotateCounterClockwise()
                    scheduleReaderSessionSynchronization()
                },
                rotateClockwise: {
                    viewModel.rotateClockwise()
                    scheduleReaderSessionSynchronization()
                },
                resetRotation: {
                    viewModel.resetRotation()
                    scheduleReaderSessionSynchronization()
                }
            ),
            onClose: {
                isShowingDisplayPanel = false
            }
        )
    }

    /// Pages, then this comic (see components/ReaderMoreMenu). Jumping to a
    /// page number stays on the page chip.
    @ViewBuilder
    private var readerMoreMenu: some View {
        if supportsBookmarks || viewModel.supportsCurrentPagePhotoSave {
            Section("Pages") {
                if supportsBookmarks {
                    Button(action: presentThumbnailBrowser) {
                        Label("Browse Thumbnails", systemImage: "square.grid.3x2")
                    }

                    bookmarksMenu
                }

                if viewModel.supportsCurrentPagePhotoSave {
                    Button(action: viewModel.saveCurrentPageToPhotoLibrary) {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isSavingCurrentPageToPhotoLibrary)
                }
            }
        }

        if viewModel.isLibraryBacked, let comic = viewModel.currentLibraryComic {
            Section("This Comic") {
                LibraryComicMenuContent(comic: comic, actions: readerComicActions)
            }
        } else if remoteProfile != nil, remoteItem != nil {
            Section("This Comic") {
                Button(action: presentRemoteInfoSheet) {
                    Label("Info", systemImage: "info.circle")
                }
            }
        }
    }

    private var bookmarksMenu: some View {
        Menu {
            if viewModel.bookmarkItems.isEmpty {
                Button("No Bookmarks") {}
                    .disabled(true)
            } else {
                ForEach(viewModel.bookmarkItems) { bookmark in
                    Button("Page \(bookmark.pageNumber)") {
                        viewModel.goToBookmark(pageIndex: bookmark.pageIndex)
                        readerSession.apply(.goToPage(bookmark.pageIndex))
                    }
                }

                Section {
                    Menu {
                        ForEach(viewModel.bookmarkItems) { bookmark in
                            Button("Page \(bookmark.pageNumber)", role: .destructive) {
                                viewModel.removeBookmark(at: bookmark.pageIndex)
                            }
                        }
                    } label: {
                        Label("Remove Bookmark", systemImage: "bookmark.slash")
                    }
                }
            }
        } label: {
            // Title, subtitle and icon as direct children show the subtitle in menus.
            Text("Bookmarks")
            Text(verbatim: bookmarkCountText)
            Image(systemName: "bookmark")
        }
    }

    private var bookmarkCountText: String {
        let count = viewModel.bookmarkItems.count
        guard let limit = viewModel.bookmarkLimit else {
            return "\(count)"
        }
        return "\(count) / \(limit)"
    }

    /// The same comic actions as the library's More menu, without delete.
    private var readerComicActions: LibraryComicActions {
        LibraryComicActions(
            toggleFavorite: { _ in viewModel.toggleFavoriteStatus() },
            toggleRead: { _ in toggleReadStatus() },
            organize: { _ in presentOrganizationSheet() },
            setRating: { rating, _ in viewModel.setRating(rating) },
            editMetadata: { _ in presentMetadataSheet() },
            showInfo: { _ in presentLocalInfoSheet() }
        )
    }

    @ViewBuilder
    private func readerBottomBar(viewportHeight: CGFloat) -> some View {
        if let document = viewModel.document,
           let currentPage = viewModel.currentPageNumber,
           let pageCount = viewModel.pageCount {
            ReaderBottomBar(
                document: document,
                currentPage: currentPage,
                pageCount: pageCount,
                viewportHeight: viewportHeight,
                showsThumbnailScrubber: !usesVerticalContinuousComicLayout,
                onPageSelected: { pageNumber in
                    viewModel.goToPage(number: pageNumber)
                    readerSession.apply(.goToPage(pageNumber - 1))
                },
                onPageIndicatorTapped: presentPageJump,
                onScrubberInteractionChanged: { isInteracting in
                    isPageNavigationInteracting = isInteracting
                }
            )
        }
    }

    @ViewBuilder
    private func readerSideOverlay(
        viewportSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        if usesVerticalContinuousComicLayout,
           let document = viewModel.document,
           let currentPage = viewModel.currentPageNumber,
           let pageCount = viewModel.pageCount,
           pageCount > 1 {
            ReaderVerticalThumbnailRail(
                document: document,
                currentPage: currentPage,
                pageCount: pageCount,
                viewportSize: viewportSize,
                safeAreaInsets: safeAreaInsets,
                onPageSelected: { pageNumber in
                    viewModel.goToPage(number: pageNumber)
                    readerSession.apply(.goToPage(pageNumber - 1))
                },
                onInteractionChanged: { isInteracting in
                    isPageNavigationInteracting = isInteracting
                }
            )
        }
    }

    @ViewBuilder
    private var readerStatusOverlay: some View {
        if let progress = viewModel.backgroundDownloadProgress {
            ReaderStatusBadge {
                HStack(spacing: 10) {
                    ProgressView(value: progress)
                        .frame(width: 48)

                    Text("Background download in progress")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
            }
        } else if let noticeMessage = viewModel.noticeMessage {
            ReaderStatusBadge {
                Text(noticeMessage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }

    private func handleReaderTap(_ tapRegion: ReaderTapRegion) {
        let configuration: ReaderTapRoutingConfiguration = viewModel.hasReaderNavigationContext
            ? .localLibrary(
                canOpenLeadingEdge: viewModel.canOpenPreviousComic,
                canOpenTrailingEdge: viewModel.canOpenNextComic
            )
            : .remoteSingleComic

        ReaderGestureCoordinator.handleTap(
            tapRegion,
            session: readerSession,
            configuration: configuration,
            onLeadingEdge: { viewModel.openPreviousComic() },
            onTrailingEdge: { viewModel.openNextComic() }
        )
    }

    private func presentThumbnailBrowser() {
        guard let document = viewModel.document else {
            return
        }
        isShowingThumbnailBrowser = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.thumbnails",
                content: AnyView(
                    ReaderThumbnailBrowserSheet(
                        document: document,
                        currentPageIndex: readerSession.state.currentPageIndex
                    ) { pageIndex in
                        updateVisiblePage(to: pageIndex)
                        isShowingThumbnailBrowser = false
                        appPresenter?.dismissSheet()
                    }
                ),
                onDismiss: {
                    isShowingThumbnailBrowser = false
                }
            )
        )
    }

    private func toggleBookmark() {
        guard viewModel.canToggleBookmarkForCurrentPage else {
            isShowingBookmarkLimitAlert = true
            return
        }
        viewModel.toggleBookmarkForCurrentPage()
    }

    /// Marking read or unread also moves the reading position; say so.
    private func toggleReadStatus() {
        guard let wasRead = viewModel.currentLibraryComic?.read else {
            return
        }
        viewModel.toggleReadStatus()
        guard viewModel.currentLibraryComic?.read == !wasRead,
              (viewModel.pageCount ?? 0) > 0 else {
            return
        }
        readStatusToastMessage = wasRead
            ? String(localized: "Marked as unread and moved to the first page")
            : String(localized: "Marked as read and moved to the last page")
    }

    private func presentLocalInfoSheet() {
        guard let descriptor = viewModel.libraryDescriptor,
              let comic = viewModel.currentLibraryComic else {
            return
        }

        let coverLocator = dependencies.libraryCoverLocator
        let metadataRootURL = dependencies.libraryStorageManager.metadataRootURL(for: descriptor)
        isShowingInfoSheet = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.info",
                content: AnyView(
                    LibraryComicInfoSheet(
                        comic: comic,
                        libraryName: descriptor.displayName,
                        coverURL: coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL),
                        coverSource: viewModel.document.map { document in
                            LocalComicCoverSource(
                                fileURL: document.fileURL,
                                cacheURL: coverLocator.plannedCoverURL(for: comic, metadataRootURL: metadataRootURL)
                            )
                        }
                    )
                ),
                onDismiss: {
                    isShowingInfoSheet = false
                }
            )
        )
    }

    private func presentRemoteInfoSheet() {
        guard let profile = remoteProfile, let item = remoteItem else {
            return
        }

        let browsingService = dependencies.remoteServerBrowsingService
        let reference = try? browsingService.makeComicFileReference(from: item)
        let readingSession = reference.flatMap { reference in
            try? dependencies.remoteReadingProgressStore.loadProgress(for: reference)
        }
        let cacheAvailability = reference.map { reference in
            RemoteServerBrowserViewModel.offlineCopyAvailability(
                browsingService.cachedAvailability(for: reference),
                isOfflineCopy: RemoteServerBrowserViewModel.offlineCopyKeys(
                    in: dependencies.remoteOfflineCopyStore,
                    profile: profile
                ).contains(RemoteOfflineCopyStore.contentKey(for: reference))
            )
        } ?? .unavailable

        isShowingInfoSheet = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.remote.info",
                content: AnyView(
                    RemoteComicInfoSheet(
                        profile: profile,
                        item: item,
                        readingSession: readingSession,
                        cacheAvailability: cacheAvailability,
                        browsingService: browsingService
                    )
                ),
                onDismiss: {
                    isShowingInfoSheet = false
                }
            )
        )
    }

    private func presentMetadataSheet() {
        guard let descriptor = viewModel.libraryDescriptor,
              let comic = viewModel.currentLibraryComic else {
            return
        }

        isShowingMetadataSheet = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.metadata",
                content: AnyView(
                    ComicMetadataEditorSheet(
                        descriptor: descriptor,
                        comic: comic,
                        dependencies: dependencies
                    ) { updatedComic in
                        viewModel.applyUpdatedComic(updatedComic)
                    }
                ),
                onDismiss: {
                    isShowingMetadataSheet = false
                }
            )
        )
    }

    private func presentOrganizationSheet() {
        guard let descriptor = viewModel.libraryDescriptor,
              let comic = viewModel.currentLibraryComic else {
            return
        }

        isShowingOrganizationSheet = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.organization",
                content: AnyView(
                    ComicOrganizationSheet(
                        descriptor: descriptor,
                        comic: comic,
                        dependencies: dependencies
                    )
                ),
                onDismiss: {
                    isShowingOrganizationSheet = false
                }
            )
        )
    }

    private var pageJumpTextBinding: Binding<String> {
        Binding(
            get: { readerSession.state.pendingPageNumberText },
            set: { readerSession.apply(.updatePendingPageNumberText($0)) }
        )
    }

    private func handleVisiblePageChange(to pageIndex: Int) {
        isContentZoomed = false
        readerSession.apply(.syncVisiblePage(pageIndex))
        viewModel.updateCurrentPage(to: pageIndex)
    }

    private func updateVisiblePage(to pageIndex: Int) {
        isContentZoomed = false
        readerSession.apply(.goToPage(pageIndex))
        viewModel.updateCurrentPage(to: pageIndex)
    }

    private func presentPageJump() {
        guard let currentPageNumber = viewModel.currentPageNumber else {
            return
        }

        readerSession.apply(.presentPageJump(defaultPageNumber: currentPageNumber))
    }

    private func submitPageJump() {
        guard let pageCount = viewModel.pageCount, pageCount > 0 else {
            return
        }

        guard let pageIndex = ReaderPageJumpResolver.pageIndex(
            from: readerSession.state.pendingPageNumberText,
            pageCount: pageCount
        ) else {
            viewModel.alert = AppAlertState(
                title: String(localized: "Invalid Page Number"),
                message: ReaderPageJumpResolver.validationMessage(pageCount: pageCount)
            )
            return
        }

        readerSession.apply(.dismissPageJump)
        updateVisiblePage(to: pageIndex)
    }

    private func scheduleReaderSessionSynchronization() {
        Task { @MainActor in
            await Task.yield()
            synchronizeReaderSession()
        }
    }

    private func startInitialLoad() {
        viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
        viewModel.loadIfNeeded()
        scheduleReaderSessionSynchronization()
    }

    private func cancelOpeningAndDismiss() {
        viewModel.cancelOpening()
        dismiss()
    }

    /// Saving closes the reader: the open request holds the old server settings,
    /// and the folder it came from reloads with the new ones.
    private func presentServerEditor(for profile: RemoteServerProfile) {
        let serverModel = RemoteServerListViewModel(
            profileStore: dependencies.remoteServerProfileStore,
            folderShortcutStore: dependencies.remoteFolderShortcutStore,
            credentialStore: dependencies.remoteServerCredentialStore,
            browsingService: dependencies.remoteServerBrowsingService,
            readingProgressStore: dependencies.remoteReadingProgressStore,
            remoteOfflineCopyStore: dependencies.remoteOfflineCopyStore,
            remoteOfflineLibrarySnapshotStore: dependencies.remoteOfflineLibrarySnapshotStore,
            remoteBackgroundImportController: dependencies.remoteBackgroundImportController
        )
        let draft = serverModel.makeEditDraft(for: profile)
        appPresenter?.presentSheet(
            .content(
                id: draft.id,
                content: AnyView(
                    RemoteServerEditorSheet(
                        draft: draft,
                        appliesSwiftUIPresentationModifiers: false
                    ) { updatedDraft in
                        let alertState = serverModel.save(draft: updatedDraft)
                        if alertState == nil {
                            appPresenter?.dismissSheet()
                            dismiss()
                        }
                        return alertState
                    }
                    .id(draft.id)
                )
            )
        )
    }

    private func synchronizeReaderSession() {
        readerSession.synchronize(
            document: viewModel.document,
            fallbackDocumentURL: viewModel.fallbackDocumentURL,
            fallbackPageCount: viewModel.fallbackPageCount,
            currentPageIndex: viewModel.currentPageIndex,
            layout: viewModel.effectiveReaderLayout
        )
    }

    private func updateIdleTimerState() {
        applyIdleTimerState(keepsScreenAwake: keepsScreenAwake)
    }

    private func reloadIdleTimerPreference() {
        let keepsScreenAwake = dependencies.readerBehaviorPreferencesStore.loadKeepsScreenAwake()
        self.keepsScreenAwake = keepsScreenAwake
        applyIdleTimerState(keepsScreenAwake: keepsScreenAwake)
    }

    private func applyIdleTimerState(keepsScreenAwake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = ReaderIdleTimerPolicy.shouldDisableIdleTimer(
            isSceneActive: scenePhase == .active,
            hasDocument: viewModel.document != nil,
            keepsScreenAwake: keepsScreenAwake
        )
    }
}

/// Shown while a comic opens. A remote comic that has to download first
/// keeps its cover, says why and how far along it is; × is the only cancel.
private struct ReaderOpeningStateView: View {
    let previewImage: UIImage?
    let title: String
    let detail: String
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: Spacing.lg) {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: min(proxy.size.width * 0.55, 260),
                            maxHeight: proxy.size.height * 0.45
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(spacing: Spacing.sm) {
                    Text("Preparing to Read")
                        .font(AppFont.headline(.semibold))
                        .foregroundStyle(.white)

                    if let normalizedProgress {
                        ProgressView(value: normalizedProgress)
                            .progressViewStyle(.linear)
                            .tint(.appJam)
                            .frame(maxWidth: 220)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    VStack(spacing: Spacing.xxs) {
                        if let progressText {
                            Text(progressText)
                                .monospacedDigit()
                        }
                        Text(detail)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(AppFont.footnote())
                    .foregroundStyle(.white.opacity(0.72))
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, Spacing.xl)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            ReaderStateTopBar(title: title, onClose: onCancel)
        }
    }

    private var normalizedProgress: Double? {
        guard let progress else {
            return nil
        }
        return min(max(progress, 0), 1)
    }

    private var progressText: String? {
        guard let normalizedProgress else {
            return nil
        }
        return "\(Int((normalizedProgress * 100).rounded()))%"
    }
}

/// Opening failed: say why, then offer Try Again and, for a remote comic,
/// Edit Server. × closes the reader.
private struct ReaderOpenFailureView: View {
    let title: String
    let message: String
    let onClose: () -> Void
    let onRetry: () -> Void
    let onEditServer: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .accessibilityHidden(true)

            Text("Comic Unavailable")
                .font(AppFont.headline(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(AppFont.callout())
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    actions
                }
                VStack(spacing: Spacing.sm) {
                    actions
                }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            ReaderStateTopBar(title: title, onClose: onClose)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: onRetry) {
            Label("Try Again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .tint(.appJam)

        if let onEditServer {
            Button(action: onEditServer) {
                Label("Edit Server", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
}

/// × and the comic's name above the opening and failure states, before the
/// reader's own bars exist.
private struct ReaderStateTopBar: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Same look as the reader's own top bar buttons.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))

            Text(title)
                .font(AppFont.headline())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .environment(\.colorScheme, .dark)
    }
}
