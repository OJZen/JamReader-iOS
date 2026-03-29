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

private struct RemoteComicReaderConfiguration {
    let fileURL: URL
    let initialDocument: ComicDocument?
    let shouldStartBackgroundDownload: Bool
}

struct RemoteComicLoadingView: View {
    @Environment(\.dismiss) private var dismiss

    private let profile: RemoteServerProfile
    private let item: RemoteDirectoryItem
    private let dependencies: AppDependencies
    private let openMode: RemoteComicOpenMode
    private let reference: RemoteComicFileReference?

    @State private var readerConfiguration: RemoteComicReaderConfiguration?
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var noticeMessage: String?
    @State private var accessState: RemoteComicAccessState = .liveRemoteCopy
    @State private var downloadProgress: Double = 0
    @State private var downloadStartTime: Date?
    @State private var downloadSpeed: String = ""
    @State private var loadingMessage = "Downloading…"
    @State private var loadTask: Task<Void, Never>?

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
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    .clear
                ],
                center: .top,
                startRadius: 24,
                endRadius: 420
            )
            .ignoresSafeArea()

            Group {
                if let readerConfiguration, let reference {
                    RemoteComicReaderView(
                        profile: profile,
                        reference: reference,
                        fileURL: readerConfiguration.fileURL,
                        displayName: item.name,
                        accessState: accessState,
                        noticeMessage: noticeMessage,
                        initialDocument: readerConfiguration.initialDocument,
                        shouldStartBackgroundDownload: readerConfiguration.shouldStartBackgroundDownload,
                        dependencies: dependencies
                    )
                } else if let loadErrorMessage {
                    RemoteComicLoadingCard {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)

                            Text("Remote Comic Unavailable")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)

                            Text(loadErrorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.78))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                RemoteComicLoadingActionButton(
                                    title: "Back",
                                    kind: .secondary,
                                    action: cancelCurrentLoadAndDismiss
                                )

                                RemoteComicLoadingActionButton(
                                    title: "Retry",
                                    kind: .primary,
                                    action: { startLoading(force: true) }
                                )
                            }
                        }
                    }
                } else {
                    RemoteComicLoadingCard {
                        VStack(spacing: 16) {
                            if downloadProgress > 0 {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(.linear)
                                    .tint(.white)
                                    .frame(width: 220)
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                if !downloadSpeed.isEmpty {
                                    Text(downloadSpeed)
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.64))
                                }
                            } else {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(loadingMessage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                RemoteComicLoadingActionButton(
                                    title: downloadProgress > 0 ? "Cancel Download" : "Cancel",
                                    kind: .secondary,
                                    action: { cancelCurrentLoad() }
                                )

                                RemoteComicLoadingActionButton(
                                    title: "Back",
                                    kind: .primary,
                                    action: cancelCurrentLoadAndDismiss
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if loadErrorMessage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startLoading(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            startLoading()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @MainActor
    private func startLoading(force: Bool = false) {
        guard force || (!isLoading && readerConfiguration == nil && loadErrorMessage == nil && loadTask == nil) else {
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            await loadComicIfNeeded(force: force)
        }
    }

    @MainActor
    private func loadComicIfNeeded(force: Bool = false) async {
        guard let reference else {
            loadErrorMessage = "This remote file is no longer a supported comic format."
            loadTask = nil
            return
        }

        isLoading = true
        if force {
            readerConfiguration = nil
        }
        loadErrorMessage = nil
        downloadProgress = 0
        downloadSpeed = ""
        downloadStartTime = nil
        loadingMessage = "Downloading…"
        defer {
            isLoading = false
            loadTask = nil
        }

        if openMode == .preferLocalCache,
           let cachedFileURL = dependencies.remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
            readerConfiguration = RemoteComicReaderConfiguration(
                fileURL: cachedFileURL,
                initialDocument: nil,
                shouldStartBackgroundDownload: false
            )
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
            let cachedAvailability = dependencies.remoteServerBrowsingService.cachedAvailability(for: reference)
            if cachedAvailability.kind == .current,
               let cachedFileURL = dependencies.remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
                readerConfiguration = RemoteComicReaderConfiguration(
                    fileURL: cachedFileURL,
                    initialDocument: nil,
                    shouldStartBackgroundDownload: false
                )
                accessState = .cachedCurrent
                noticeMessage = "Opened the downloaded copy saved on this device."
                return
            }

            if dependencies.remoteServerBrowsingService.supportsStreamingOpen(for: reference),
               dependencies.comicDocumentLoader.supportsRemoteStreaming(for: reference.fileName) {
                loadingMessage = "Preparing Pages…"
                let documentURL = dependencies.remoteServerBrowsingService.plannedCachedFileURL(for: reference)
                let reader = try await dependencies.remoteServerBrowsingService.makeStreamingFileReader(
                    for: profile,
                    reference: reference
                )

                do {
                    let document = try await dependencies.comicDocumentLoader.loadRemoteDocument(
                        named: reference.fileName,
                        documentURL: documentURL,
                        reader: reader
                    )
                    try Task.checkCancellation()

                    readerConfiguration = RemoteComicReaderConfiguration(
                        fileURL: documentURL,
                        initialDocument: document,
                        shouldStartBackgroundDownload: true
                    )
                    accessState = .liveRemoteCopy
                    noticeMessage = nil
                    return
                } catch {
                    try? await reader.close()
                    throw error
                }
            }

            loadingMessage = "Downloading…"
            let startTime = Date()
            downloadStartTime = startTime
            let fileSize = reference.fileSize ?? 0
            let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                for: profile,
                reference: reference,
                progressHandler: { @Sendable [startTime] progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        if fileSize > 0 {
                            let elapsed = Date().timeIntervalSince(startTime)
                            if elapsed > 0.5 {
                                let bytesDownloaded = Double(fileSize) * progress
                                let bytesPerSecond = bytesDownloaded / elapsed
                                self.downloadSpeed = Self.formatSpeed(bytesPerSecond)
                            }
                        }
                    }
                }
            )
            try Task.checkCancellation()

            readerConfiguration = RemoteComicReaderConfiguration(
                fileURL: result.localFileURL,
                initialDocument: nil,
                shouldStartBackgroundDownload: false
            )
            let resolvedAccessState = RemoteComicAccessState(source: result.source)
            accessState = resolvedAccessState
            noticeMessage = resolvedAccessState.transientNoticeMessage
        } catch is CancellationError {
            if readerConfiguration == nil {
                loadErrorMessage = "The remote comic open was canceled."
            }
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func cancelCurrentLoad(showCancellationMessage: Bool = true) {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        downloadProgress = 0
        downloadSpeed = ""
        downloadStartTime = nil

        if showCancellationMessage, readerConfiguration == nil {
            loadErrorMessage = "The remote comic open was canceled."
        }
    }

    @MainActor
    private func cancelCurrentLoadAndDismiss() {
        cancelCurrentLoad(showCancellationMessage: false)
        dismiss()
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}

private struct RemoteComicLoadingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            content()
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            Color.white.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 24, y: 18)
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
    }
}

private struct RemoteComicLoadingActionButton: View {
    enum Kind {
        case primary
        case secondary
    }

    let title: String
    let kind: Kind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(kind == .primary ? Color.black : Color.white)
        .background(
            kind == .primary ? Color.white : Color.white.opacity(0.10),
            in: Capsule()
        )
        .overlay {
            if kind == .secondary {
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
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
    private let initialDocument: ComicDocument?
    private let shouldStartBackgroundDownload: Bool
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
    @State private var backgroundDownloadTask: Task<Void, Never>?
    @State private var backgroundDownloadProgress: Double?
    @State private var isContentZoomed = false
    @State private var isDismissGestureActive = false
    @State private var isProgressScrubberInteracting = false

    init(
        profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        fileURL: URL,
        displayName: String,
        accessState: RemoteComicAccessState,
        noticeMessage: String?,
        initialDocument: ComicDocument? = nil,
        shouldStartBackgroundDownload: Bool = false,
        dependencies: AppDependencies
    ) {
        self.profile = profile
        self.reference = reference
        self.fileURL = fileURL
        self.displayName = displayName
        self.initialNoticeMessage = noticeMessage
        self.initialDocument = initialDocument
        self.shouldStartBackgroundDownload = shouldStartBackgroundDownload
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
        .pullDownToDismiss(
            isEnabled: !readerSession.state.isPageJumpPresented && !isProgressScrubberInteracting,
            isZoomed: isContentZoomed,
            onDismissGestureActiveChanged: { active in
                isDismissGestureActive = active
            },
            onDismiss: {
                var t = Transaction(animation: .none)
                withTransaction(t) { dismiss() }
            }
        )
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
            backgroundDownloadTask?.cancel()
            closeResources(for: document)
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
            DispatchQueue.main.async {
                persistProgress()
                hideReaderChrome()
            }
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
            onBack: dismiss.callAsFunction,
            onMenu: {
                readerSession.apply(.setChromeVisible(true))
                isShowingReaderControls = true
            },
            isMenuDisabled: document == nil
        )
    }

    @ViewBuilder
    private var readerBottomBar: some View {
        if let document,
           let currentPage = currentPageNumber,
           let pageCount = document.pageCount {
            ReaderBottomBar(
                document: document,
                currentPage: currentPage,
                pageCount: pageCount,
                onPageSelected: { pageNumber in
                    updateVisiblePage(to: pageNumber - 1)
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
        if let backgroundDownloadProgress {
            ReaderStatusBadge {
                HStack(spacing: 10) {
                    if backgroundDownloadProgress > 0 {
                        ProgressView(value: backgroundDownloadProgress)
                            .frame(width: 56)
                    } else {
                        ProgressView()
                    }

                    Text(backgroundDownloadStatusText(for: backgroundDownloadProgress))
                        .font(.caption.weight(.semibold))
                }
            }
        }

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
            isHorizontalScrollingDisabled: isDismissGestureActive,
            onPageChanged: handleVisiblePageChange(to:),
            onReaderTap: handleReaderTap,
            onZoomStateChanged: { zoomed in
                DispatchQueue.main.async {
                    isContentZoomed = zoomed
                }
            }
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
            if let initialDocument {
                let preferredPageIndex = initialPageIndex(for: initialDocument.pageCount)
                presentDocument(initialDocument, preferredPageIndex: preferredPageIndex)
                startBackgroundDownloadIfNeeded()
                return
            }

            let loadedDocument = try dependencies.comicDocumentLoader.loadDocument(at: fileURL)
            presentDocument(
                loadedDocument,
                preferredPageIndex: initialPageIndex(for: loadedDocument.pageCount)
            )
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Open Remote Comic",
                message: error.localizedDescription
            )
        }
    }

    private func handleReaderTap(_ region: ReaderTapRegion) {
        ReaderGestureCoordinator.handleTap(
            region,
            session: readerSession,
            configuration: .remoteSingleComic
        )
    }

    private func hideReaderChrome() {
        ReaderGestureCoordinator.hideChrome(session: readerSession)
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

    @MainActor
    private func presentDocument(
        _ loadedDocument: ComicDocument,
        preferredPageIndex: Int
    ) {
        let previousDocument = document
        document = loadedDocument
        readerSession.updateDescriptor(
            .resolved(
                document: loadedDocument,
                currentPageIndex: preferredPageIndex,
                layout: effectiveReaderLayout
            ),
            preferredPageIndex: preferredPageIndex
        )
        normalizeBookmarks(for: loadedDocument.pageCount)
        persistProgress(force: true)
        closeResources(for: previousDocument, keeping: loadedDocument)
    }

    private func backgroundDownloadStatusText(for progress: Double) -> String {
        if progress > 0 {
            return "Saving Offline Copy \(Int(progress * 100))%"
        }

        return "Saving Offline Copy"
    }

    @MainActor
    private func startBackgroundDownloadIfNeeded() {
        guard shouldStartBackgroundDownload,
              initialDocument != nil,
              backgroundDownloadTask == nil else {
            return
        }

        backgroundDownloadProgress = 0
        backgroundDownloadTask = Task(priority: .utility) {
            defer {
                Task { @MainActor in
                    self.backgroundDownloadTask = nil
                }
            }

            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.backgroundDownloadProgress = nil
                }
                return
            }

            do {
                let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                    for: profile,
                    reference: reference,
                    progressHandler: { @Sendable progress in
                        Task { @MainActor in
                            self.backgroundDownloadProgress = progress
                        }
                    }
                )

                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.backgroundDownloadProgress = nil
                    }
                    return
                }

                switch result.source {
                case .downloaded, .cachedCurrent:
                    let loadedDocument = try dependencies.comicDocumentLoader.loadDocument(at: result.localFileURL)
                    await MainActor.run {
                        let preferredPageIndex = min(
                            self.currentPageIndex,
                            max((loadedDocument.pageCount ?? 1) - 1, 0)
                        )
                        self.presentDocument(loadedDocument, preferredPageIndex: preferredPageIndex)
                        self.accessState = .cachedCurrent
                        self.transientNoticeMessage = "Offline copy ready."
                        self.backgroundDownloadProgress = nil
                    }
                case .cachedFallback:
                    await MainActor.run {
                        self.backgroundDownloadProgress = nil
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.backgroundDownloadProgress = nil
                }
            } catch {
                await MainActor.run {
                    self.backgroundDownloadProgress = nil
                }
            }
        }
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
            let preferredPageIndex = min(preservedPageIndex, max((loadedDocument.pageCount ?? 1) - 1, 0))
            presentDocument(loadedDocument, preferredPageIndex: preferredPageIndex)

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
        isContentZoomed = false
        readerSession.apply(.syncVisiblePage(pageIndex))
    }

    private func updateVisiblePage(to pageIndex: Int) {
        isContentZoomed = false
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

    private func closeResources(
        for document: ComicDocument?,
        keeping keptDocument: ComicDocument? = nil
    ) {
        guard let document,
              case .imageSequence(let imageDocument) = document else {
            return
        }

        if let keptDocument,
           case .imageSequence(let keptImageDocument) = keptDocument,
           ObjectIdentifier(imageDocument.pageSource) == ObjectIdentifier(keptImageDocument.pageSource) {
            return
        }

        let pageSource = imageDocument.pageSource
        Task {
            await pageSource.close()
        }
    }
}

private enum RemoteReaderSecondaryAction {
    case thumbnails
}
