import SwiftUI
import UIKit

struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let dependencies: AppDependencies

    @StateObject private var viewModel: ComicReaderViewModel
    @StateObject private var readerSession: ReaderSessionController
    @State private var isShowingMetadataSheet = false
    @State private var isShowingQuickMetadataSheet = false
    @State private var isShowingOrganizationSheet = false
    @State private var isShowingReaderControls = false
    @State private var isShowingThumbnailBrowser = false
    @State private var pendingReaderAction: ReaderSecondaryAction?
    @State private var isContentZoomed = false
    @State private var isDismissGestureActive = false
    @State private var isProgressScrubberInteracting = false
    @State private var containerWidth: CGFloat = 0

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext? = nil,
        onComicUpdated: ((LibraryComic) -> Void)? = nil,
        dependencies: AppDependencies
    ) {
        self.dependencies = dependencies
        let initialLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: comic.type)
        let initialDescriptor = ReaderContentDescriptor.placeholder(
            documentURL: URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true),
            pageCount: max(comic.pageCount ?? max(comic.currentPage, 1), 1),
            initialPageIndex: max(comic.currentPage - 1, 0),
            layout: initialLayout
        )
        _viewModel = StateObject(
            wrappedValue: ComicReaderViewModel(
                descriptor: descriptor,
                comic: comic,
                navigationContext: navigationContext,
                storageManager: dependencies.libraryStorageManager,
                databaseWriter: dependencies.libraryDatabaseWriter,
                documentLoader: dependencies.comicDocumentLoader,
                readerLayoutPreferencesStore: dependencies.readerLayoutPreferencesStore,
                onComicUpdated: onComicUpdated
            )
        )
        _readerSession = StateObject(
            wrappedValue: ReaderSessionController(descriptor: initialDescriptor)
        )
    }

    var body: some View {
        ReaderSurface(
            isInteractionLocked: readerSession.state.isPageJumpPresented,
            isChromeHidden: !readerSession.state.isChromeVisible
        ) {
            Group {
                if viewModel.isLoading {
                    ReaderFallbackStateView(
                        title: "Opening Comic",
                        systemImage: nil,
                        message: nil,
                        showsProgress: true
                    )
                } else if let document = viewModel.document {
                    readerContent(for: document)
                } else {
                    ReaderFallbackStateView(
                        title: "Comic Unavailable",
                        systemImage: "book.closed",
                        message: "The selected comic could not be opened."
                    )
                }
            }
        } topBar: {
            readerTopBar
        } bottomBar: {
            readerBottomBar
        } statusOverlay: {
            EmptyView()
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
        .readContainerWidth(into: $containerWidth)
        .pullDownToDismiss(
            isEnabled: !readerSession.state.isPageJumpPresented && !isProgressScrubberInteracting && !isAnySheetPresented,
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
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
            viewModel.loadIfNeeded()
            synchronizeReaderSession()
        }
        .onAppear {
            updateIdleTimerState()
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
            synchronizeReaderSession()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.persistCurrentProgress()
        }
        .onChange(of: scenePhase) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: viewModel.document != nil) { _, _ in
            updateIdleTimerState()
        }
        .onChange(of: supportsDoublePageSpread) { _, _ in
            viewModel.setAllowsDoublePageSpread(supportsDoublePageSpread)
            synchronizeReaderSession()
        }
        .onChange(of: viewModel.document?.fileURL) { _, _ in
            synchronizeReaderSession()
        }
        .onChange(of: viewModel.readerLayout) { _, _ in
            synchronizeReaderSession()
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
        .sheet(isPresented: $isShowingThumbnailBrowser) {
            if let document = viewModel.document {
                ReaderThumbnailBrowserSheet(
                    document: document,
                    currentPageIndex: readerSession.state.currentPageIndex
                ) { pageIndex in
                    updateVisiblePage(to: pageIndex)
                    isShowingThumbnailBrowser = false
                }
            }
        }
        .sheet(isPresented: $isShowingReaderControls) {
            readerControlsSheet
        }
        .sheet(isPresented: $isShowingQuickMetadataSheet) {
            ReaderQuickMetadataSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            ) { updatedComic in
                viewModel.applyUpdatedComic(updatedComic)
            }
        }
        .sheet(isPresented: $isShowingMetadataSheet) {
            ComicMetadataEditorSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            ) { updatedComic in
                viewModel.applyUpdatedComic(updatedComic)
            }
        }
        .sheet(isPresented: $isShowingOrganizationSheet) {
            ComicOrganizationSheet(
                descriptor: viewModel.descriptor,
                comic: viewModel.comic,
                dependencies: dependencies
            )
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: isShowingReaderControls) { _, isPresented in
            if isPresented {
                readerSession.apply(.setChromeVisible(true))
                return
            }

            guard !isPresented, let pendingReaderAction else {
                return
            }

            self.pendingReaderAction = nil
            switch pendingReaderAction {
            case .quickMetadata:
                isShowingQuickMetadataSheet = true
            case .metadata:
                isShowingMetadataSheet = true
            case .organization:
                isShowingOrganizationSheet = true
            case .thumbnails:
                isShowingThumbnailBrowser = true
            }
        }
    }

    private var supportsDoublePageSpread: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularReaderLayoutMinWidth)
    }

    private var showsThumbnailShortcut: Bool {
        supportsDoublePageSpread && (viewModel.pageCount ?? 0) > 1
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        ReaderDocumentContentView(
            document: document,
            pageIndex: readerSession.state.currentPageIndex,
            layout: readerSession.state.layout,
            isHorizontalScrollingDisabled: isDismissGestureActive,
            onPageChanged: handleVisiblePageChange(to:),
            onReaderTap: handleReaderTap,
            onZoomStateChanged: { zoomed in
                DispatchQueue.main.async {
                    isContentZoomed = zoomed
                }
            }
        ) { unsupportedDocument in
            ReaderFallbackStateView(
                title: "Reader Not Ready",
                systemImage: "shippingbox",
                message: unsupportedReaderMessage(for: unsupportedDocument)
            )
        }
    }

    private func unsupportedReaderMessage(for unsupportedDocument: UnsupportedComicDocument) -> String {
        let fileExtension = unsupportedDocument.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)

        if fileExtension.isEmpty {
            return unsupportedDocument.reason
        }

        return "\(fileExtension.uppercased()) reading support is still being ported.\n\n\(unsupportedDocument.reason)"
    }

    private var readerControlsSheet: some View {
        ReaderControlsSheet(
            pageState: ReaderControlsPageState(
                pageIndicatorText: viewModel.pageIndicatorText,
                currentPageNumber: viewModel.currentPageNumber,
                pageCount: viewModel.pageCount,
                currentPageIsBookmarked: viewModel.currentPageIsBookmarked,
                bookmarkItems: viewModel.bookmarkItems
            ),
            displayState: ReaderControlsDisplayState(
                fitMode: readerSession.state.layout.fitMode,
                pagingMode: readerSession.state.layout.pagingMode,
                spreadMode: readerSession.state.layout.spreadMode,
                readingDirection: readerSession.state.layout.readingDirection,
                coverAsSinglePage: readerSession.state.layout.coverAsSinglePage,
                rotation: readerSession.state.layout.rotation
            ),
            capabilities: ReaderControlsCapabilities(
                supportsImageLayoutControls: viewModel.supportsImageLayoutControls,
                supportsDoublePageSpread: supportsDoublePageSpread,
                supportsRotationControls: viewModel.supportsRotationControls
            ),
            actions: ReaderControlsActions(
                onDone: { isShowingReaderControls = false },
                onOpenThumbnails: {
                    pendingReaderAction = .thumbnails
                    isShowingReaderControls = false
                },
                onGoToBookmark: { pageIndex in
                    viewModel.goToBookmark(pageIndex: pageIndex)
                    readerSession.apply(.goToPage(pageIndex))
                    isShowingReaderControls = false
                },
                onGoToPageNumber: { pageNumber in
                    viewModel.goToPage(number: pageNumber)
                    readerSession.apply(.goToPage(pageNumber - 1))
                    isShowingReaderControls = false
                },
                onToggleBookmark: viewModel.toggleBookmarkForCurrentPage,
                onSetFitMode: { fitMode in
                    viewModel.setFitMode(fitMode)
                    synchronizeReaderSession()
                },
                onSetPagingMode: { pagingMode in
                    viewModel.setPagingMode(pagingMode)
                    synchronizeReaderSession()
                },
                onSetSpreadMode: { spreadMode in
                    viewModel.setSpreadMode(spreadMode)
                    synchronizeReaderSession()
                },
                onSetReadingDirection: { readingDirection in
                    viewModel.setReadingDirection(readingDirection)
                    synchronizeReaderSession()
                },
                onSetCoverAsSinglePage: { coverAsSinglePage in
                    viewModel.setCoverAsSinglePage(coverAsSinglePage)
                    synchronizeReaderSession()
                },
                onRotateCounterClockwise: {
                    viewModel.rotateCounterClockwise()
                    synchronizeReaderSession()
                },
                onRotateClockwise: {
                    viewModel.rotateClockwise()
                    synchronizeReaderSession()
                },
                onResetRotation: {
                    viewModel.resetRotation()
                    synchronizeReaderSession()
                },
                onToggleFavorite: viewModel.toggleFavoriteStatus,
                onToggleReadStatus: viewModel.toggleReadStatus,
                onSetRating: viewModel.setRating,
                onOpenQuickMetadata: {
                    pendingReaderAction = .quickMetadata
                    isShowingReaderControls = false
                },
                onOpenMetadata: {
                    pendingReaderAction = .metadata
                    isShowingReaderControls = false
                },
                onOpenOrganization: {
                    pendingReaderAction = .organization
                    isShowingReaderControls = false
                }
            ),
            metadata: ReaderControlsMetadata(
                isFavorite: viewModel.isFavorite,
                isRead: viewModel.comic.read,
                rating: viewModel.rating
            ),
            fileInfo: ReaderControlsFileInfo(
                fileName: viewModel.comic.fileName,
                fileExtension: viewModel.document?.fileURL.pathExtension,
                pageCount: viewModel.pageCount,
                series: viewModel.comic.series,
                volume: viewModel.comic.volume,
                addedAt: viewModel.comic.addedAt,
                lastOpenedAt: viewModel.comic.lastOpenedAt,
                fileURL: viewModel.document?.fileURL,
                coverDocument: viewModel.document
            )
        )
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
            secondaryAccessibilityLabel: "Browse Pages",
            onSecondaryAction: showsThumbnailShortcut ? {
                readerSession.setChromeVisible(true)
                isShowingThumbnailBrowser = true
            } : nil,
            onMenu: {
                readerSession.setChromeVisible(true)
                isShowingReaderControls = true
            },
            isMenuDisabled: viewModel.document == nil
        )
    }

    @ViewBuilder
    private var readerBottomBar: some View {
        if let document = viewModel.document,
           let currentPage = viewModel.currentPageNumber,
           let pageCount = viewModel.pageCount {
            ReaderBottomBar(
                document: document,
                currentPage: currentPage,
                pageCount: pageCount,
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

    private func handleReaderTap(_ tapRegion: ReaderTapRegion) {
        ReaderGestureCoordinator.handleTap(
            tapRegion,
            session: readerSession,
            configuration: .localLibrary(
                canOpenLeadingEdge: viewModel.canOpenPreviousComic,
                canOpenTrailingEdge: viewModel.canOpenNextComic
            ),
            onLeadingEdge: { viewModel.openPreviousComic() },
            onTrailingEdge: { viewModel.openNextComic() }
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
                title: "Invalid Page Number",
                message: ReaderPageJumpResolver.validationMessage(pageCount: pageCount)
            )
            return
        }

        readerSession.apply(.dismissPageJump)
        updateVisiblePage(to: pageIndex)
    }

    private func synchronizeReaderSession() {
        readerSession.synchronize(
            document: viewModel.document,
            fallbackDocumentURL: URL(fileURLWithPath: viewModel.descriptor.sourcePath, isDirectory: true),
            fallbackPageCount: max(viewModel.comic.pageCount ?? max(viewModel.comic.currentPage, 1), 1),
            currentPageIndex: viewModel.currentPageIndex,
            layout: viewModel.effectiveReaderLayout
        )
    }

    private func updateIdleTimerState() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && viewModel.document != nil
    }
}

private enum ReaderSecondaryAction {
    case quickMetadata
    case metadata
    case organization
    case thumbnails
}
