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
                    ProgressView("Opening Comic")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document = viewModel.document {
                    readerContent(for: document)
                } else {
                    ContentUnavailableView(
                        "Comic Unavailable",
                        systemImage: "book.closed",
                        description: Text("The selected comic could not be opened.")
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
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
        .onChange(of: horizontalSizeClass) { _, _ in
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

            readerSession.apply(.syncVisiblePage(newValue))
            ReaderGestureCoordinator.hideChrome(session: readerSession)
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
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        ReaderDocumentContentView(
            document: document,
            pageIndex: readerSession.state.currentPageIndex,
            layout: readerSession.state.layout,
            onPageChanged: handleVisiblePageChange(to:),
            onReaderTap: handleReaderTap
        ) { unsupportedDocument in
            ContentUnavailableView(
                "Reader Not Ready",
                systemImage: "shippingbox",
                description: Text("`. \(unsupportedDocument.fileExtension)` files are already indexed by the library, but archive page extraction is still being ported.\n\n\(unsupportedDocument.reason)")
            )
        }
    }

    private var readerControlsSheet: some View {
        ReaderControlsSheet(
            pageIndicatorText: viewModel.pageIndicatorText,
            currentPageNumber: viewModel.currentPageNumber,
            pageCount: viewModel.pageCount,
            currentPageIsBookmarked: viewModel.currentPageIsBookmarked,
            bookmarkItems: viewModel.bookmarkItems,
            isFavorite: viewModel.isFavorite,
            isRead: viewModel.comic.read,
            rating: viewModel.rating,
            supportsImageLayoutControls: viewModel.supportsImageLayoutControls,
            supportsDoublePageSpread: supportsDoublePageSpread,
            supportsRotationControls: viewModel.supportsRotationControls,
            fitMode: readerSession.state.layout.fitMode,
            pagingMode: readerSession.state.layout.pagingMode,
            spreadMode: readerSession.state.layout.spreadMode,
            readingDirection: readerSession.state.layout.readingDirection,
            coverAsSinglePage: readerSession.state.layout.coverAsSinglePage,
            rotation: readerSession.state.layout.rotation,
            onDone: { isShowingReaderControls = false },
            onToggleFavorite: viewModel.toggleFavoriteStatus,
            onToggleReadStatus: viewModel.toggleReadStatus,
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
            },
            onOpenThumbnails: {
                pendingReaderAction = .thumbnails
                isShowingReaderControls = false
            },
            onToggleBookmark: viewModel.toggleBookmarkForCurrentPage,
            onSetRating: viewModel.setRating,
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
            }
        )
    }

    private var readerTopBar: some View {
        ReaderTopBar(
            title: viewModel.navigationTitle,
            onBack: dismiss.callAsFunction,
            onMenu: {
                readerSession.setChromeVisible(true)
                isShowingReaderControls = true
            },
            isMenuDisabled: viewModel.document == nil
        )
    }

    @ViewBuilder
    private var readerBottomBar: some View {
        if let currentPage = viewModel.currentPageNumber, let pageCount = viewModel.pageCount {
            ReaderBottomBar(
                currentPage: currentPage,
                pageCount: pageCount,
                onPageSelected: { pageNumber in
                    viewModel.goToPage(number: pageNumber)
                    readerSession.apply(.goToPage(pageNumber - 1))
                },
                onPageIndicatorTapped: presentPageJump
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
        readerSession.apply(.syncVisiblePage(pageIndex))
        viewModel.updateCurrentPage(to: pageIndex)
    }

    private func updateVisiblePage(to pageIndex: Int) {
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
            viewModel.alert = LibraryAlertState(
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
