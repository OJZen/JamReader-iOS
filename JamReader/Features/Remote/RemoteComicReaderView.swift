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
        openMode: RemoteComicOpenMode = .automatic,
        referenceOverride: RemoteComicFileReference? = nil
    ) {
        self.profile = profile
        self.item = item
        self.dependencies = dependencies
        self.openMode = openMode
        self.reference = referenceOverride
            ?? (try? dependencies.remoteServerBrowsingService.makeComicFileReference(from: item))
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
                        errorStateContent(message: loadErrorMessage)
                    }
                } else {
                    RemoteComicLoadingCard {
                        loadingStateContent
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

    @ViewBuilder
    private var loadingStateContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            loadingHeader(
                title: item.name,
                subtitle: loadingMessage
            )

            if downloadProgress > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.white)

                    RemoteComicLoadingMetricRow(
                        label: "Progress",
                        value: "\(Int(downloadProgress * 100))%"
                    )

                    if !downloadSpeed.isEmpty {
                        RemoteComicLoadingMetricRow(
                            label: "Speed",
                            value: downloadSpeed
                        )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)

                    Text("Connecting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }

            RemoteComicLoadingActionButton(
                title: "Cancel",
                kind: .primary,
                action: cancelCurrentLoadAndDismiss
            )
        }
    }

    private func errorStateContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            loadingHeader(
                title: item.name,
                subtitle: "Remote Comic Unavailable"
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 24, height: 24)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    private func loadingHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
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
            do {
                readerConfiguration = try validatedReaderConfiguration(
                    fileURL: cachedFileURL,
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
            } catch {
                try? dependencies.remoteServerBrowsingService.clearCachedComic(for: reference)
                loadErrorMessage = "The saved offline copy could not be opened. Download it again from the remote server."
            }
            return
        }

        do {
            let cachedAvailability = dependencies.remoteServerBrowsingService.cachedAvailability(for: reference)
            if cachedAvailability.kind == .current,
               let cachedFileURL = dependencies.remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
                do {
                    readerConfiguration = try validatedReaderConfiguration(
                        fileURL: cachedFileURL,
                        shouldStartBackgroundDownload: false
                    )
                    accessState = .cachedCurrent
                    noticeMessage = "Opened the downloaded copy saved on this device."
                    return
                } catch {
                    try? dependencies.remoteServerBrowsingService.clearCachedComic(for: reference)
                }
            }

            if await dependencies.remoteServerBrowsingService.supportsStreamingOpen(
                for: reference,
                profile: profile
            ),
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
                } catch is CancellationError {
                    try? await reader.close()
                    throw CancellationError()
                } catch {
                    try? await reader.close()
                    guard profile.providerKind == .webdav else {
                        throw error
                    }
                    loadingMessage = "Downloading…"
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

            do {
                readerConfiguration = try validatedReaderConfiguration(
                    fileURL: result.localFileURL,
                    shouldStartBackgroundDownload: false
                )
            } catch {
                try? dependencies.remoteServerBrowsingService.clearCachedComic(for: reference)
                throw error
            }
            let resolvedAccessState = RemoteComicAccessState(source: result.source)
            accessState = resolvedAccessState
            noticeMessage = resolvedAccessState.transientNoticeMessage
        } catch is CancellationError {
            if readerConfiguration == nil {
                loadErrorMessage = "The remote comic open was canceled."
            }
        } catch {
            loadErrorMessage = error.userFacingMessage
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

    private func validatedReaderConfiguration(
        fileURL: URL,
        shouldStartBackgroundDownload: Bool
    ) throws -> RemoteComicReaderConfiguration {
        RemoteComicReaderConfiguration(
            fileURL: fileURL,
            initialDocument: try dependencies.comicDocumentLoader.loadDocument(at: fileURL),
            shouldStartBackgroundDownload: shouldStartBackgroundDownload
        )
    }
}

private struct RemoteComicLoadingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading) {
            content()
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
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
        .foregroundStyle(.white)
        .background(
            kind == .primary ? Color.white.opacity(0.16) : Color.white.opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(kind == .primary ? 0.12 : 0.16), lineWidth: 1)
        }
    }
}

private struct RemoteComicLoadingMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.62))

            Spacer(minLength: 0)

            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.86))
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
    @State private var alert: AppAlertState?
    @State private var lastPersistedProgressSnapshot: ReaderProgressPersistenceSnapshot?
    @State private var pendingProgressPersistenceTask: Task<Void, Never>?
    @State private var accessState: RemoteComicAccessState
    @State private var transientNoticeMessage: String?
    @State private var backgroundDownloadTask: Task<Void, Never>?
    @State private var backgroundDownloadProgress: Double?
    @State private var isContentZoomed = false
    @State private var isDismissGestureActive = false
    @State private var isProgressScrubberInteracting = false
    @State private var containerWidth: CGFloat = 0

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
                    ReaderFallbackStateView(
                        title: "Opening Remote Comic",
                        systemImage: nil,
                        message: nil,
                        showsProgress: true
                    )
                } else if let document {
                    readerContent(for: document)
                } else {
                    ReaderFallbackStateView(
                        title: "Comic Unavailable",
                        systemImage: "book.closed",
                        message: "The downloaded remote comic could not be opened."
                    )
                }
            }
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
                    currentPageNumber: currentPageNumber ?? 1,
                    pageCount: document?.pageCount ?? 1,
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
        .navigationTitle(displayName)
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
                pageState: ReaderControlsPageState(
                    pageIndicatorText: pageIndicatorText,
                    currentPageNumber: currentPageNumber,
                    pageCount: document?.pageCount,
                    currentPageIsBookmarked: currentPageIsBookmarked,
                    bookmarkItems: bookmarkItems
                ),
                displayState: ReaderControlsDisplayState(
                    fitMode: effectiveReaderLayout.fitMode,
                    pagingMode: effectiveReaderLayout.pagingMode,
                    spreadMode: effectiveReaderLayout.spreadMode,
                    readingDirection: effectiveReaderLayout.readingDirection,
                    coverAsSinglePage: effectiveReaderLayout.coverAsSinglePage,
                    rotation: effectiveReaderLayout.rotation
                ),
                capabilities: ReaderControlsCapabilities(
                    supportsImageLayoutControls: supportsImageLayoutControls,
                    supportsDoublePageSpread: supportsDoublePageSpread,
                    supportsRotationControls: supportsRotationControls,
                    supportsPageNavigation: document?.pageCount != nil,
                    supportsBookmarks: document?.pageCount != nil
                ),
                actions: ReaderControlsActions(
                    onDone: { isShowingReaderControls = false },
                    onOpenThumbnails: {
                        pendingReaderAction = .thumbnails
                        isShowingReaderControls = false
                    },
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
                    onToggleBookmark: toggleBookmark,
                    onSetFitMode: setFitMode,
                    onSetPagingMode: setPagingMode,
                    onSetSpreadMode: setSpreadMode,
                    onSetReadingDirection: setReadingDirection,
                    onSetCoverAsSinglePage: setCoverAsSinglePage,
                    onRotateCounterClockwise: rotateCounterClockwise,
                    onRotateClockwise: rotateClockwise,
                    onResetRotation: resetRotation
                ),
                fileInfo: ReaderControlsFileInfo(
                    fileName: displayName,
                    fileExtension: document?.fileURL.pathExtension,
                    pageCount: document?.pageCount,
                    series: nil,
                    volume: nil,
                    addedAt: nil,
                    lastOpenedAt: nil,
                    fileURL: document?.fileURL,
                    coverDocument: document
                )
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

    private var isAnySheetPresented: Bool {
        isShowingReaderControls || isShowingThumbnailBrowser
    }

    private var supportsDoublePageSpread: Bool {
        horizontalSizeClass == .regular
            && (containerWidth == 0 || containerWidth >= AppLayout.regularReaderLayoutMinWidth)
    }

    private var showsThumbnailShortcut: Bool {
        supportsDoublePageSpread && (document?.pageCount ?? 0) > 1
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
        switch document {
        case .pdf?, .imageSequence?:
            return effectiveReaderLayout.pagingMode != .verticalContinuous
        case .ebook?, .unsupported?, nil:
            return false
        }
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
            secondarySystemImage: showsThumbnailShortcut ? "square.grid.3x2" : nil,
            secondaryAccessibilityLabel: "Browse Pages",
            onSecondaryAction: showsThumbnailShortcut ? {
                readerSession.apply(.setChromeVisible(true))
                isShowingThumbnailBrowser = true
            } : nil,
            onMenu: {
                readerSession.apply(.setChromeVisible(true))
                isShowingReaderControls = true
            },
            isMenuDisabled: document == nil
        )
    }

    @ViewBuilder
    private func readerBottomBar(viewportHeight: CGFloat) -> some View {
        if let document,
           let currentPage = currentPageNumber,
           let pageCount = document.pageCount {
            ReaderBottomBar(
                document: document,
                currentPage: currentPage,
                pageCount: pageCount,
                viewportHeight: viewportHeight,
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
        if isRefreshingRemoteCopy {
            ReaderStatusBadge {
                HStack(spacing: 10) {
                    ProgressView()

                    Text("Refreshing Remote Copy")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
            }
        } else if let backgroundDownloadProgress {
            ReaderStatusBadge {
                HStack(spacing: 10) {
                    if backgroundDownloadProgress > 0 {
                        ProgressView(value: backgroundDownloadProgress)
                            .frame(width: 52)

                        Text(backgroundDownloadStatusText(for: backgroundDownloadProgress))
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)

                        Text("\(Int(backgroundDownloadProgress * 100))%")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        ProgressView()

                        Text(backgroundDownloadStatusText(for: backgroundDownloadProgress))
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                    }
                }
            }
        } else if let transientNoticeMessage {
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
            ReaderFallbackStateView(
                title: "Unsupported Comic",
                systemImage: "doc.badge.questionmark",
                message: unsupportedDocument.reason
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
            alert = AppAlertState(
                title: "Failed to Open Remote Comic",
                message: error.userFacingMessage
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
            alert = AppAlertState(
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

    private func backgroundDownloadStatusText(for _: Double) -> String {
        return "Background download in progress"
    }

    @MainActor
    private func startBackgroundDownloadIfNeeded() {
        guard shouldStartBackgroundDownload,
              initialDocument != nil,
              backgroundDownloadTask == nil else {
            return
        }

        backgroundDownloadProgress = 0
        let task = Task(priority: .utility) {
            defer {
                dependencies.remoteServerBrowsingService.unregisterAutomaticCacheTask(for: reference)
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
        backgroundDownloadTask = task
        dependencies.remoteServerBrowsingService.registerAutomaticCacheTask(
            for: reference,
            cancellation: { task.cancel() }
        )
    }

    private func persistProgress(force: Bool = false) {
        guard let document else {
            return
        }
        if case .unsupported = document {
            return
        }

        let requestedSnapshot = progressSnapshot(for: document)
        if !force, lastPersistedProgressSnapshot == requestedSnapshot {
            return
        }

        pendingProgressPersistenceTask?.cancel()

        if force {
            writeProgress(for: requestedSnapshot, document: document)
            return
        }

        pendingProgressPersistenceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                writeProgress(for: requestedSnapshot, document: document)
            }
        }
    }

    private func writeProgress(
        for snapshot: ReaderProgressPersistenceSnapshot,
        document: ComicDocument
    ) {
        guard lastPersistedProgressSnapshot != snapshot else {
            return
        }

        let progress = readingProgress(for: snapshot, document: document)

        do {
            try dependencies.remoteReadingProgressStore.saveProgress(
                progress,
                for: reference,
                profile: profile,
                bookmarkPageIndices: snapshot.bookmarkPageIndices
            )
            lastPersistedProgressSnapshot = snapshot
        } catch {
            alert = AppAlertState(
                title: "Failed to Save Remote Progress",
                message: error.userFacingMessage
            )
        }
    }

    private func progressSnapshot(for document: ComicDocument) -> ReaderProgressPersistenceSnapshot {
        let snapshotPageCount = max(document.pageCount ?? 1, 1)
        return ReaderProgressFactory.snapshot(
            pageIndex: currentPageIndex,
            pageCount: snapshotPageCount,
            bookmarkPageIndices: bookmarkPageIndices
        )
    }

    private func readingProgress(
        for snapshot: ReaderProgressPersistenceSnapshot,
        document: ComicDocument
    ) -> ComicReadingProgress {
        switch document {
        case .ebook:
            return ReaderProgressFactory.nonPaginatedProgress(
                currentPosition: max(snapshot.pageIndex + 1, 1)
            )
        case .pdf, .imageSequence:
            return ReaderProgressFactory.progress(
                forPageIndex: snapshot.pageIndex,
                pageCount: max(document.pageCount ?? 1, 1)
            )
        case .unsupported:
            return ReaderProgressFactory.nonPaginatedProgress()
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
            alert = AppAlertState(
                title: "Failed to Refresh Remote Comic",
                message: error.userFacingMessage
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
