import SwiftUI
import UIKit

enum RemoteComicAccessState: Equatable {
    case liveRemoteCopy
    case cachedCurrent
    case cachedFallback(String)

    init(source: RemoteComicDownloadResult.Source) {
        switch source {
        case .downloaded:
            self = .liveRemoteCopy
        case .cachedCurrent:
            self = .cachedCurrent
        case .cachedFallback(let message):
            self = .cachedFallback(message)
        }
    }

    var transientNoticeMessage: String? {
        switch self {
        case .liveRemoteCopy:
            return nil
        case .cachedCurrent:
            return "Opened the downloaded copy saved on this device."
        case .cachedFallback(let message):
            return message
        }
    }
}

enum RemoteComicOpenMode: Hashable {
    case automatic
    case preferLocalCache
}

struct RemoteComicLoadingView: View {
    private let profile: RemoteServerProfile
    private let item: RemoteDirectoryItem
    private let dependencies: AppDependencies
    private let openMode: RemoteComicOpenMode
    private let reference: RemoteComicFileReference?

    @State private var localFileURL: URL?
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var noticeMessage: String?
    @State private var accessState: RemoteComicAccessState = .liveRemoteCopy

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        dependencies: AppDependencies,
        openMode: RemoteComicOpenMode = .automatic
    ) {
        self.profile = profile
        self.item = item
        self.dependencies = dependencies
        self.openMode = openMode
        self.reference = try? dependencies.remoteServerBrowsingService.makeComicFileReference(from: item)
    }

    var body: some View {
        Group {
            if let localFileURL, let reference {
                RemoteComicReaderView(
                    profile: profile,
                    reference: reference,
                    fileURL: localFileURL,
                    displayName: item.name,
                    accessState: accessState,
                    noticeMessage: noticeMessage,
                    dependencies: dependencies
                )
            } else if let loadErrorMessage {
                ContentUnavailableView(
                    "Remote Comic Unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text(loadErrorMessage)
                )
            } else {
                ProgressView("Downloading Remote Comic")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loadErrorMessage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadComicIfNeeded(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await loadComicIfNeeded()
        }
    }

    @MainActor
    private func loadComicIfNeeded(force: Bool = false) async {
        guard force || (!isLoading && localFileURL == nil && loadErrorMessage == nil) else {
            return
        }

        guard let reference else {
            loadErrorMessage = "This remote file is no longer a supported comic format."
            return
        }

        isLoading = true
        loadErrorMessage = nil
        defer {
            isLoading = false
        }

        if openMode == .preferLocalCache,
           let cachedFileURL = dependencies.remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
            localFileURL = cachedFileURL
            let availability = dependencies.remoteServerBrowsingService.cachedAvailability(for: reference)
            switch availability.kind {
            case .unavailable:
                accessState = .liveRemoteCopy
                noticeMessage = nil
            case .current:
                accessState = .cachedCurrent
                noticeMessage = "Opened the downloaded copy saved on this device."
            case .stale:
                let message = "Opened an older downloaded copy saved on this device."
                accessState = .cachedFallback(message)
                noticeMessage = message
            }
            return
        }

        do {
            let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                for: profile,
                reference: reference
            )
            localFileURL = result.localFileURL
            let resolvedAccessState = RemoteComicAccessState(source: result.source)
            accessState = resolvedAccessState
            noticeMessage = resolvedAccessState.transientNoticeMessage
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }
}

struct RemoteComicReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private let profile: RemoteServerProfile
    private let reference: RemoteComicFileReference
    private let fileURL: URL
    private let displayName: String
    private let initialNoticeMessage: String?
    private let dependencies: AppDependencies
    private let initialStoredProgress: RemoteComicReadingSession?

    @StateObject private var readerSession: ReaderSessionController
    @State private var document: ComicDocument?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var isRefreshingRemoteCopy = false
    @State private var isShowingReaderControls = false
    @State private var isShowingThumbnailBrowser = false
    @State private var pendingReaderAction: RemoteReaderSecondaryAction?
    @State private var bookmarkPageIndices: [Int]
    @State private var alert: RemoteAlertState?
    @State private var lastPersistedProgressSnapshot: ReaderProgressPersistenceSnapshot?
    @State private var pendingProgressPersistenceTask: Task<Void, Never>?
    @State private var accessState: RemoteComicAccessState
    @State private var transientNoticeMessage: String?

    init(
        profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        fileURL: URL,
        displayName: String,
        accessState: RemoteComicAccessState,
        noticeMessage: String?,
        dependencies: AppDependencies
    ) {
        self.profile = profile
        self.reference = reference
        self.fileURL = fileURL
        self.displayName = displayName
        self.initialNoticeMessage = noticeMessage
        self.dependencies = dependencies
        let storedProgress = try? dependencies.remoteReadingProgressStore.loadProgress(for: reference)
        self.initialStoredProgress = storedProgress
        let initialLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: .comic)
        let initialDescriptor = ReaderContentDescriptor.placeholder(
            documentURL: fileURL,
            pageCount: max(storedProgress?.pageCount ?? 1, 1),
            initialPageIndex: Self.initialPageIndex(from: storedProgress),
            layout: initialLayout
        )
        _accessState = State(initialValue: accessState)
        _transientNoticeMessage = State(initialValue: noticeMessage)
        _bookmarkPageIndices = State(
            initialValue: ReaderBookmarkNormalizer.normalized(storedProgress?.bookmarkPageIndices ?? [])
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
                if isLoading {
                    ProgressView("Opening Remote Comic")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    readerContent(for: document)
                } else {
                    ContentUnavailableView(
                        "Comic Unavailable",
                        systemImage: "book.closed",
                        description: Text("The downloaded remote comic could not be opened.")
                    )
                }
            }
        } topBar: {
            readerTopBar
        } bottomBar: {
            readerBottomBar
        } statusOverlay: {
            readerStatusOverlay
        } modalOverlay: {
            if readerSession.state.isPageJumpPresented {
                ReaderPageJumpOverlay(
                    pageNumberText: pageJumpTextBinding,
                    currentPageNumber: currentPageNumber ?? 1,
                    pageCount: document?.pageCount ?? 1,
                    onCancel: { readerSession.apply(.dismissPageJump) },
                    onJump: submitPageJump
                )
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadIfNeeded()
            updateIdleTimerState()
            synchronizeReaderSession()
        }
        .onAppear {
            updateIdleTimerState()
            scheduleNoticeDismissalIfNeeded()
            synchronizeReaderSession()
        }
        .onDisappear {
            persistProgress(force: true)
            pendingProgressPersistenceTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                persistProgress(force: true)
            }
            updateIdleTimerState()
        }
        .onChange(of: document != nil) { _, _ in
            updateIdleTimerState()
            synchronizeReaderSession()
        }
        .onChange(of: readerSession.state.layout) { _, _ in
            synchronizeReaderSession()
        }
        .onChange(of: supportsDoublePageSpread) { _, _ in
            synchronizeReaderSession()
        }
        .onChange(of: currentPageIndex) { _, _ in
            persistProgress()
            hideReaderChrome()
        }
        .onChange(of: transientNoticeMessage) { _, message in
            guard message != nil else {
                return
            }

            scheduleNoticeDismissalIfNeeded()
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
            case .thumbnails:
                isShowingThumbnailBrowser = true
            }
        }
        .sheet(isPresented: $isShowingThumbnailBrowser) {
            if let document {
                ReaderThumbnailBrowserSheet(
                    document: document,
                    currentPageIndex: currentPageIndex
                ) { pageIndex in
                    updateVisiblePage(to: pageIndex)
                    isShowingThumbnailBrowser = false
                }
            }
        }
        .sheet(isPresented: $isShowingReaderControls) {
            ReaderControlsSheet(
                pageIndicatorText: pageIndicatorText,
                currentPageNumber: currentPageNumber,
                pageCount: document?.pageCount,
                currentPageIsBookmarked: currentPageIsBookmarked,
                bookmarkItems: bookmarkItems,
                supportsImageLayoutControls: supportsImageLayoutControls,
                supportsDoublePageSpread: supportsDoublePageSpread,
                supportsRotationControls: supportsRotationControls,
                fitMode: effectiveReaderLayout.fitMode,
                pagingMode: effectiveReaderLayout.pagingMode,
                spreadMode: effectiveReaderLayout.spreadMode,
                readingDirection: effectiveReaderLayout.readingDirection,
                coverAsSinglePage: effectiveReaderLayout.coverAsSinglePage,
                rotation: effectiveReaderLayout.rotation,
                onDone: { isShowingReaderControls = false },
                onOpenThumbnails: {
                    pendingReaderAction = .thumbnails
                    isShowingReaderControls = false
                },
                onToggleBookmark: toggleBookmark,
                onGoToBookmark: { pageIndex in
                    updateVisiblePage(to: pageIndex)
                    persistProgress(force: true)
                    isShowingReaderControls = false
                },
                onGoToPageNumber: { pageNumber in
                    updateVisiblePage(to: pageNumber - 1)
                    persistProgress(force: true)
                    isShowingReaderControls = false
                },
                onSetFitMode: setFitMode,
                onSetPagingMode: setPagingMode,
                onSetSpreadMode: setSpreadMode,
                onSetReadingDirection: setReadingDirection,
                onSetCoverAsSinglePage: setCoverAsSinglePage,
                onRotateCounterClockwise: rotateCounterClockwise,
                onRotateClockwise: rotateClockwise,
                onResetRotation: resetRotation
            )
        }
        .alert(item: $alert) { alert in
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

    private var currentPageIndex: Int {
        readerSession.state.currentPageIndex
    }

    private var readerLayout: ReaderDisplayLayout {
        readerSession.state.layout
    }

    private var effectiveReaderLayout: ReaderDisplayLayout {
        readerLayout.normalized(allowingDoublePageSpread: supportsDoublePageSpread)
    }

    private var supportsImageLayoutControls: Bool {
        if let document, case .imageSequence = document {
            return true
        }

        return false
    }

    private var supportsRotationControls: Bool {
        guard document != nil else {
            return false
        }

        return effectiveReaderLayout.pagingMode != .verticalContinuous
    }

    private var currentPageIsBookmarked: Bool {
        bookmarkPageIndices.contains(currentPageIndex)
    }

    private var bookmarkItems: [ReaderBookmarkItem] {
        ReaderBookmarkSupport.items(from: bookmarkPageIndices)
    }

    private var pageIndicatorText: String? {
        ReaderPageIndicatorFormatter.text(
            for: document,
            currentPageIndex: currentPageIndex,
            layout: effectiveReaderLayout
        )
    }

    private var readerTopBar: some View {
        ReaderTopBar(
            title: displayName,
            subtitle: nil,
            onBack: dismiss.callAsFunction,
            onTrailingAction: {
                readerSession.apply(.setChromeVisible(true))
                isShowingReaderControls = true
            },
            isTrailingDisabled: document == nil
        ) {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var readerBottomBar: some View {
        if let pageIndicatorText {
            ReaderPageJumpBar(pageIndicatorText: pageIndicatorText, onTap: presentPageJump)
        }
    }

    @ViewBuilder
    private var readerStatusOverlay: some View {
        if isRefreshingRemoteCopy {
            ReaderStatusBadge {
                ProgressView("Refreshing Remote Copy")
                    .font(.caption.weight(.semibold))
            }
        }

        if let transientNoticeMessage {
            ReaderStatusBadge {
                Text(transientNoticeMessage)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        ReaderDocumentContentView(
            document: document,
            pageIndex: currentPageIndex,
            layout: effectiveReaderLayout,
            onPageChanged: handleVisiblePageChange(to:),
            onReaderTap: handleReaderTap
        ) { unsupportedDocument in
            ContentUnavailableView(
                "Unsupported Comic",
                systemImage: "doc.badge.questionmark",
                description: Text(unsupportedDocument.reason)
            )
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let loadedDocument = try dependencies.comicDocumentLoader.loadDocument(at: fileURL)
            document = loadedDocument
            readerSession.updateDescriptor(
                .resolved(
                    document: loadedDocument,
                    currentPageIndex: initialPageIndex(for: loadedDocument.pageCount),
                    layout: effectiveReaderLayout
                ),
                preferredPageIndex: initialPageIndex(for: loadedDocument.pageCount)
            )
            normalizeBookmarks(for: loadedDocument.pageCount)
            persistProgress(force: true)
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Open Remote Comic",
                message: error.localizedDescription
            )
        }
    }

    private func handleReaderTap(_ region: ReaderTapRegion) {
        let action = ReaderTapRouter.action(
            for: region,
            isChromeVisible: readerSession.state.isChromeVisible,
            configuration: .remoteSingleComic
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            switch action {
            case .none:
                break
            case .toggleChrome:
                readerSession.apply(.toggleChrome)
            case .hideChrome:
                readerSession.apply(.hideChrome)
            case .invokeLeadingEdgeAction, .invokeTrailingEdgeAction:
                break
            }
        }
    }

    private func hideReaderChrome() {
        guard readerSession.state.isChromeVisible else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            readerSession.apply(.hideChrome)
        }
    }

    private var currentPageNumber: Int? {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return nil
        }

        return min(currentPageIndex + 1, pageCount)
    }

    private func updateCurrentPage(to pageIndex: Int) {
        guard pageIndex >= 0 else {
            return
        }

        if let pageCount = document?.pageCount, pageCount > 0 {
            readerSession.apply(.goToPage(min(pageIndex, pageCount - 1)))
        } else {
            readerSession.apply(.goToPage(pageIndex))
        }
    }

    private func toggleBookmark() {
        bookmarkPageIndices = ReaderBookmarkSupport.toggled(
            bookmarkPageIndices,
            at: currentPageIndex,
            pageCount: document?.pageCount
        )
        persistProgress(force: true)
    }

    private func presentPageJump() {
        guard let currentPageNumber else {
            return
        }

        readerSession.apply(.presentPageJump(defaultPageNumber: currentPageNumber))
    }

    private func submitPageJump() {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return
        }

        guard let pageIndex = ReaderPageJumpResolver.pageIndex(
            from: readerSession.state.pendingPageNumberText,
            pageCount: pageCount
        ) else {
            alert = RemoteAlertState(
                title: "Invalid Page Number",
                message: ReaderPageJumpResolver.validationMessage(pageCount: pageCount)
            )
            return
        }

        updateVisiblePage(to: pageIndex)
        readerSession.apply(.dismissPageJump)
        persistProgress(force: true)
    }

    private func setPagingMode(_ pagingMode: ReaderPagingMode) {
        updateLayout { updatedLayout in
            guard updatedLayout.pagingMode != pagingMode else {
                return
            }

            updatedLayout.pagingMode = pagingMode
            if pagingMode == .verticalContinuous {
                updatedLayout.spreadMode = .singlePage
            }
        }
    }

    private func setFitMode(_ fitMode: ReaderFitMode) {
        updateLayout { updatedLayout in
            guard updatedLayout.fitMode != fitMode else {
                return
            }

            updatedLayout.fitMode = fitMode
        }
    }

    private func setReadingDirection(_ readingDirection: ReaderReadingDirection) {
        updateLayout { updatedLayout in
            guard updatedLayout.readingDirection != readingDirection else {
                return
            }

            updatedLayout.readingDirection = readingDirection
        }
    }

    private func setSpreadMode(_ spreadMode: ReaderSpreadMode) {
        updateLayout { updatedLayout in
            guard updatedLayout.spreadMode != spreadMode else {
                return
            }

            updatedLayout.spreadMode = spreadMode
        }
    }

    private func setCoverAsSinglePage(_ coverAsSinglePage: Bool) {
        updateLayout { updatedLayout in
            guard updatedLayout.coverAsSinglePage != coverAsSinglePage else {
                return
            }

            updatedLayout.coverAsSinglePage = coverAsSinglePage
        }
    }

    private func rotateCounterClockwise() {
        updateLayout { updatedLayout in
            updatedLayout.rotation = updatedLayout.rotation.rotatedCounterClockwise()
        }
    }

    private func rotateClockwise() {
        updateLayout { updatedLayout in
            updatedLayout.rotation = updatedLayout.rotation.rotatedClockwise()
        }
    }

    private func resetRotation() {
        updateLayout { updatedLayout in
            guard updatedLayout.rotation != .degrees0 else {
                return
            }

            updatedLayout.rotation = .degrees0
        }
    }

    private func updateLayout(_ mutate: (inout ReaderDisplayLayout) -> Void) {
        var updatedLayout = readerLayout
        let previousLayout = updatedLayout
        mutate(&updatedLayout)
        guard updatedLayout != previousLayout else {
            return
        }

        readerSession.updateLayout(updatedLayout)
        persistLayout()
    }

    private func persistLayout() {
        dependencies.readerLayoutPreferencesStore.saveLayout(readerLayout, for: .comic)
    }

    private static func initialPageIndex(
        from storedProgress: RemoteComicReadingSession?
    ) -> Int {
        guard let storedProgress else {
            return 0
        }

        return storedProgress.pageIndex
    }

    private func initialPageIndex(for pageCount: Int?) -> Int {
        let storedPageIndex = Self.initialPageIndex(from: initialStoredProgress)
        guard let pageCount, pageCount > 0 else {
            return max(0, storedPageIndex)
        }

        return min(max(0, storedPageIndex), pageCount - 1)
    }

    private func persistProgress(force: Bool = false) {
        guard let pageCount = document?.pageCount else {
            return
        }

        let requestedSnapshot = ReaderProgressFactory.snapshot(
            pageIndex: currentPageIndex,
            pageCount: pageCount,
            bookmarkPageIndices: bookmarkPageIndices
        )
        if !force, lastPersistedProgressSnapshot == requestedSnapshot {
            return
        }

        pendingProgressPersistenceTask?.cancel()

        if force {
            writeProgress(for: requestedSnapshot, pageCount: pageCount)
            return
        }

        pendingProgressPersistenceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                writeProgress(for: requestedSnapshot, pageCount: pageCount)
            }
        }
    }

    private func writeProgress(
        for snapshot: ReaderProgressPersistenceSnapshot,
        pageCount: Int
    ) {
        guard lastPersistedProgressSnapshot != snapshot else {
            return
        }

        let progress = ReaderProgressFactory.progress(
            forPageIndex: snapshot.pageIndex,
            pageCount: pageCount
        )

        do {
            try dependencies.remoteReadingProgressStore.saveProgress(
                progress,
                for: reference,
                profile: profile,
                bookmarkPageIndices: snapshot.bookmarkPageIndices
            )
            lastPersistedProgressSnapshot = snapshot
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Save Remote Progress",
                message: error.localizedDescription
            )
        }
    }

    private func updateIdleTimerState() {
        let shouldDisableIdleTimer = scenePhase == .active && document != nil
        if UIApplication.shared.isIdleTimerDisabled != shouldDisableIdleTimer {
            UIApplication.shared.isIdleTimerDisabled = shouldDisableIdleTimer
        }
    }

    private func scheduleNoticeDismissalIfNeeded() {
        guard transientNoticeMessage != nil else {
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    transientNoticeMessage = nil
                }
            }
        }
    }

    @MainActor
    private func refreshRemoteCopy() async {
        guard !isRefreshingRemoteCopy else {
            return
        }

        isRefreshingRemoteCopy = true
        let preservedPageIndex = currentPageIndex
        defer {
            isRefreshingRemoteCopy = false
        }

        do {
            let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                for: profile,
                reference: reference,
                forceRefresh: true
            )
            let loadedDocument = try dependencies.comicDocumentLoader.loadDocument(at: result.localFileURL)
            document = loadedDocument
            readerSession.updateDescriptor(
                .resolved(
                    document: loadedDocument,
                    currentPageIndex: min(preservedPageIndex, max((loadedDocument.pageCount ?? 1) - 1, 0)),
                    layout: effectiveReaderLayout
                ),
                preferredPageIndex: min(preservedPageIndex, max((loadedDocument.pageCount ?? 1) - 1, 0))
            )
            normalizeBookmarks(for: loadedDocument.pageCount)
            persistProgress(force: true)

            switch result.source {
            case .downloaded:
                accessState = .liveRemoteCopy
                transientNoticeMessage = "Remote copy refreshed."
            case .cachedCurrent:
                accessState = .cachedCurrent
                transientNoticeMessage = "The local copy is already current."
            case .cachedFallback(let message):
                accessState = .cachedFallback(message)
                transientNoticeMessage = message
            }
            scheduleNoticeDismissalIfNeeded()
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Refresh Remote Comic",
                message: error.localizedDescription
            )
        }
    }

    private var pageJumpTextBinding: Binding<String> {
        Binding(
            get: { readerSession.state.pendingPageNumberText },
            set: { readerSession.apply(.updatePendingPageNumberText($0)) }
        )
    }

    private func handleVisiblePageChange(to pageIndex: Int) {
        readerSession.apply(.syncVisiblePage(pageIndex))
    }

    private func updateVisiblePage(to pageIndex: Int) {
        updateCurrentPage(to: pageIndex)
    }

    private func synchronizeReaderSession() {
        readerSession.synchronize(
            document: document,
            fallbackDocumentURL: fileURL,
            fallbackPageCount: max(initialStoredProgress?.pageCount ?? 1, 1),
            currentPageIndex: currentPageIndex,
            layout: effectiveReaderLayout
        )
    }

    private func normalizeBookmarks(for pageCount: Int?) {
        let normalizedBookmarks = ReaderBookmarkNormalizer.normalized(
            bookmarkPageIndices,
            pageCount: pageCount
        )
        if normalizedBookmarks != bookmarkPageIndices {
            bookmarkPageIndices = normalizedBookmarks
        }
    }
}

private enum RemoteReaderSecondaryAction {
    case thumbnails
}
