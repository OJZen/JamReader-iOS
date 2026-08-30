import SwiftUI
import UIKit

struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let dependencies: AppDependencies
    private let openingPreviewImage: UIImage?

    @StateObject private var viewModel: ComicReaderViewModel
    @StateObject private var readerSession: ReaderSessionController
    @State private var isShowingMetadataSheet = false
    @State private var isShowingQuickMetadataSheet = false
    @State private var isShowingOrganizationSheet = false
    @State private var isShowingReaderControls = false
    @State private var isShowingThumbnailBrowser = false
    @State private var isContentZoomed = false
    @State private var isDismissGestureActive = false
    @State private var isProgressScrubberInteracting = false
    @State private var keepsScreenAwake: Bool

    @MainActor
    init(
        request: ComicOpenRequest,
        dependencies: AppDependencies,
        openingPreviewImage: UIImage? = nil
    ) {
        self.dependencies = dependencies
        self.openingPreviewImage = openingPreviewImage
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
                        title: viewModel.loadingMessage,
                        progress: viewModel.loadingProgress,
                        onCancel: cancelOpeningAndDismiss
                    )
                } else {
                    ReaderFallbackStateView(
                        title: String(localized: "Comic Unavailable"),
                        systemImage: "book.closed",
                        message: viewModel.failureMessage
                            ?? String(localized: "The selected comic could not be opened.")
                    )
                }
            }
            .background(Color.black.ignoresSafeArea())
            .id(readerRenderIdentity)
        } topBar: {
            readerTopBar
        } bottomBar: { viewportSize in
            readerBottomBar(viewportHeight: viewportSize.height)
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
            isEnabled: !readerSession.state.isPageJumpPresented && !isProgressScrubberInteracting && !isAnySheetPresented,
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
    }

    private var supportsDoublePageSpread: Bool {
        horizontalSizeClass == .regular
    }

    private var showsThumbnailShortcut: Bool {
        supportsDoublePageSpread && (viewModel.pageCount ?? 0) > 1
    }

    private var dismissGestureDirection: ReaderDismissGestureDirection {
        guard readerSession.state.layout.pagingMode == .verticalContinuous,
              case .imageSequence(let imageSequence) = viewModel.document,
              imageSequence.usesComicImageLayout
        else {
            return .down
        }

        return .right
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

    private var readerControlsSheet: some View {
        PresentedReaderControlsSheet(
            viewModel: viewModel,
            actions: readerControlsActions
        )
    }

    private var readerControlsActions: ReaderControlsActions {
        var actions = ReaderControlsActions(
            onDone: dismissReaderControls,
            onOpenThumbnails: {
                presentThumbnailBrowser()
            },
            onGoToBookmark: { pageIndex in
                viewModel.goToBookmark(pageIndex: pageIndex)
                readerSession.apply(.goToPage(pageIndex))
                dismissReaderControls()
            },
            onGoToPageNumber: { pageNumber in
                viewModel.goToPage(number: pageNumber)
                readerSession.apply(.goToPage(pageNumber - 1))
                dismissReaderControls()
            },
            onToggleBookmark: viewModel.toggleBookmarkForCurrentPage,
            onSetFitMode: { fitMode in
                viewModel.setFitMode(fitMode)
                scheduleReaderSessionSynchronization()
            },
            onSetPagingMode: { pagingMode in
                viewModel.setPagingMode(pagingMode)
                scheduleReaderSessionSynchronization()
            },
            onSetSpreadMode: { spreadMode in
                viewModel.setSpreadMode(spreadMode)
                scheduleReaderSessionSynchronization()
            },
            onSetReadingDirection: { readingDirection in
                viewModel.setReadingDirection(readingDirection)
                scheduleReaderSessionSynchronization()
            },
            onSetCoverAsSinglePage: { coverAsSinglePage in
                viewModel.setCoverAsSinglePage(coverAsSinglePage)
                scheduleReaderSessionSynchronization()
            },
            onSetPageSpacingEnabled: { pageSpacingEnabled in
                viewModel.setPageSpacingEnabled(pageSpacingEnabled)
                scheduleReaderSessionSynchronization()
            },
            onRotateCounterClockwise: {
                viewModel.rotateCounterClockwise()
                scheduleReaderSessionSynchronization()
            },
            onRotateClockwise: {
                viewModel.rotateClockwise()
                scheduleReaderSessionSynchronization()
            },
            onResetRotation: {
                viewModel.resetRotation()
                scheduleReaderSessionSynchronization()
            }
        )

        guard viewModel.isLibraryBacked else {
            return actions
        }

        actions.onToggleFavorite = {
            viewModel.toggleFavoriteStatus()
        }
        actions.onToggleReadStatus = {
            viewModel.toggleReadStatus()
        }
        actions.onSetRating = { rating in
            viewModel.setRating(rating)
        }
        actions.onOpenQuickMetadata = {
            presentQuickMetadataSheet()
        }
        actions.onOpenMetadata = {
            presentMetadataSheet()
        }
        actions.onOpenOrganization = {
            presentOrganizationSheet()
        }
        return actions
    }

    private var isAnySheetPresented: Bool {
        isShowingReaderControls || isShowingMetadataSheet ||
        isShowingQuickMetadataSheet || isShowingOrganizationSheet ||
        isShowingThumbnailBrowser
    }

    private var readerTopBar: some View {
        ReaderTopBar(
            title: viewModel.navigationTitle,
            onBack: dismiss.callAsFunction,
            secondarySystemImage: showsThumbnailShortcut ? "square.grid.3x2" : nil,
            secondaryAccessibilityLabel: String(localized: "Browse Pages"),
            onSecondaryAction: showsThumbnailShortcut ? {
                readerSession.setChromeVisible(true)
                presentThumbnailBrowser()
            } : nil,
            savePageSystemImage: viewModel.isSavingCurrentPageToPhotoLibrary ? "hourglass" : "square.and.arrow.down",
            savePageAccessibilityLabel: String(localized: "Save Page to Photos"),
            onSavePage: viewModel.supportsCurrentPagePhotoSave ? {
                viewModel.saveCurrentPageToPhotoLibrary()
            } : nil,
            isSavePageDisabled: viewModel.isSavingCurrentPageToPhotoLibrary,
            onMenu: {
                presentReaderControls()
            },
            isMenuDisabled: viewModel.document == nil
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
                onPageSelected: { pageNumber in
                    viewModel.goToPage(number: pageNumber)
                    readerSession.apply(.goToPage(pageNumber - 1))
                },
                onPageIndicatorTapped: presentPageJump,
                onScrubberInteractionChanged: { isInteracting in
                    isProgressScrubberInteracting = isInteracting
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

    private func presentReaderControls() {
        isShowingReaderControls = true
        readerSession.apply(.setChromeVisible(true))
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.controls",
                content: AnyView(readerControlsSheet),
                onDismiss: {
                    isShowingReaderControls = false
                }
            )
        )
    }

    private func dismissReaderControls() {
        isShowingReaderControls = false
        appPresenter?.dismissSheet()
    }

    private func presentQuickMetadataSheet() {
        guard let descriptor = viewModel.libraryDescriptor,
              let comic = viewModel.currentLibraryComic else {
            return
        }

        isShowingReaderControls = false
        isShowingQuickMetadataSheet = true
        appPresenter?.presentSheet(
            .content(
                id: "reader.local.quickMetadata",
                content: AnyView(
                    ReaderQuickMetadataSheet(
                        descriptor: descriptor,
                        comic: comic,
                        dependencies: dependencies
                    ) { updatedComic in
                        viewModel.applyUpdatedComic(updatedComic)
                    }
                ),
                onDismiss: {
                    isShowingQuickMetadataSheet = false
                }
            )
        )
    }

    private func presentMetadataSheet() {
        guard let descriptor = viewModel.libraryDescriptor,
              let comic = viewModel.currentLibraryComic else {
            return
        }

        isShowingReaderControls = false
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

        isShowingReaderControls = false
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

/// UIKit presents reader controls in a separate hosting tree, so the sheet must
/// observe the reader model instead of retaining values captured when it opened.
private struct PresentedReaderControlsSheet: View {
    @ObservedObject var viewModel: ComicReaderViewModel
    let actions: ReaderControlsActions

    var body: some View {
        ReaderControlsSheet(
            pageState: ReaderControlsPageState(
                pageIndicatorText: viewModel.pageIndicatorText,
                currentPageNumber: viewModel.currentPageNumber,
                pageCount: viewModel.pageCount,
                currentPageIsBookmarked: viewModel.currentPageIsBookmarked,
                bookmarkItems: viewModel.bookmarkItems
            ),
            displayState: ReaderControlsDisplayState(
                fitMode: viewModel.effectiveReaderLayout.fitMode,
                pagingMode: viewModel.effectiveReaderLayout.pagingMode,
                spreadMode: viewModel.effectiveReaderLayout.spreadMode,
                readingDirection: viewModel.effectiveReaderLayout.readingDirection,
                coverAsSinglePage: viewModel.effectiveReaderLayout.coverAsSinglePage,
                pageSpacingEnabled: viewModel.effectiveReaderLayout.pageSpacingEnabled,
                rotation: viewModel.effectiveReaderLayout.rotation
            ),
            capabilities: ReaderControlsCapabilities(
                supportsImageLayoutControls: viewModel.supportsImageLayoutControls,
                supportsDoublePageSpread: viewModel.allowsDoublePageSpread,
                supportsRotationControls: viewModel.supportsRotationControls,
                supportsPageNavigation: viewModel.pageCount != nil,
                supportsBookmarks: viewModel.pageCount != nil
            ),
            actions: actions,
            metadata: metadata,
            fileInfo: fileInfo
        )
    }

    private var metadata: ReaderControlsMetadata? {
        guard viewModel.isLibraryBacked else {
            return nil
        }
        return ReaderControlsMetadata(
            isFavorite: viewModel.isFavorite,
            isRead: viewModel.currentLibraryComic?.read,
            rating: viewModel.rating
        )
    }

    private var fileInfo: ReaderControlsFileInfo {
        ReaderControlsFileInfo(
            fileName: viewModel.fileName,
            fileExtension: viewModel.document?.fileURL.pathExtension,
            pageCount: viewModel.pageCount,
            series: viewModel.fileSeries,
            volume: viewModel.fileVolume,
            addedAt: viewModel.fileAddedAt,
            lastOpenedAt: viewModel.fileLastOpenedAt,
            fileURL: viewModel.document?.fileURL,
            coverDocument: viewModel.document
        )
    }
}

private struct ReaderOpeningStateView: View {
    let previewImage: UIImage?
    let title: String
    let progress: Double?
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.22), .clear, .black.opacity(0.36)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        }
                }

                loadingPanel
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black.ignoresSafeArea())
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

    private var loadingPanel: some View {
        VStack(spacing: Spacing.sm) {
            if let normalizedProgress {
                ProgressView(value: normalizedProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 160)
            } else {
                ProgressView()
                    .tint(.white)
                    .controlSize(.regular)
            }

            Text(title)
                .font(AppFont.headline(.semibold))
                .foregroundStyle(.white)

            if let progressText {
                Text(progressText)
                    .font(AppFont.caption(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button(role: .cancel, action: onCancel) {
                Text("Cancel")
                    .font(AppFont.callout(.semibold))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.white.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
