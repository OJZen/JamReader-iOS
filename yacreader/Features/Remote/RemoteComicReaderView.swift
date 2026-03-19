import SwiftUI
import UIKit

struct RemoteComicLoadingView: View {
    private let profile: RemoteServerProfile
    private let item: RemoteDirectoryItem
    private let dependencies: AppDependencies
    private let reference: RemoteComicFileReference?

    @State private var localFileURL: URL?
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var noticeMessage: String?

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        dependencies: AppDependencies
    ) {
        self.profile = profile
        self.item = item
        self.dependencies = dependencies
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

        do {
            let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                for: profile,
                reference: reference
            )
            localFileURL = result.localFileURL
            switch result.source {
            case .downloaded, .cachedCurrent:
                noticeMessage = nil
            case .cachedFallback(let message):
                noticeMessage = message
            }
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
    @State private var isShowingThumbnailBrowser = false
    @State private var bookmarkPageIndices: [Int]
    @State private var alert: RemoteAlertState?
    @State private var lastPersistedProgressSnapshot: ReaderProgressPersistenceSnapshot?
    @State private var pendingProgressPersistenceTask: Task<Void, Never>?
    @State private var transientNoticeMessage: String?

    init(
        profile: RemoteServerProfile,
        reference: RemoteComicFileReference,
        fileURL: URL,
        displayName: String,
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
            onBack: dismiss.callAsFunction
        ) {
            Button {
                Task {
                    await refreshRemoteCopy()
                }
            } label: {
                if isRefreshingRemoteCopy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                }
            }
            .disabled(isRefreshingRemoteCopy)
        }
    }

    @ViewBuilder
    private var readerBottomBar: some View {
        if let pageIndicatorText {
            ReaderChromeBar {
                HStack(spacing: 16) {
                    Menu {
                        if let document, document.pageCount ?? 0 > 1 {
                            Section("Navigation") {
                                Button {
                                    isShowingThumbnailBrowser = true
                                } label: {
                                    Label("Page Browser", systemImage: "rectangle.grid.2x2")
                                }

                                Button(action: presentPageJump) {
                                    Label("Go to Page", systemImage: "number")
                                }
                            }
                        }

                        Section("Remote") {
                            Button {
                                Task {
                                    await refreshRemoteCopy()
                                }
                            } label: {
                                Label("Refresh Remote Copy", systemImage: "arrow.clockwise")
                            }
                            .disabled(isRefreshingRemoteCopy)
                        }

                        Section("Reading Status") {
                            Button(action: toggleBookmark) {
                                Label(
                                    currentPageIsBookmarked ? "Remove Current Bookmark" : "Bookmark Current Page",
                                    systemImage: currentPageIsBookmarked ? "bookmark.slash" : "bookmark"
                                )
                            }
                        }

                        if !bookmarkItems.isEmpty {
                            Section("Bookmarks") {
                                ForEach(bookmarkItems) { bookmark in
                                    Button {
                                        updateVisiblePage(to: bookmark.pageIndex)
                                        persistProgress(force: true)
                                    } label: {
                                        Label("Page \(bookmark.pageNumber)", systemImage: "bookmark.fill")
                                    }
                                }
                            }
                        }

                        if supportsImageLayoutControls {
                            Section("Paging") {
                                ForEach(ReaderPagingMode.allCases, id: \.self) { pagingMode in
                                    layoutOptionButton(
                                        title: pagingMode.title,
                                        isSelected: effectiveReaderLayout.pagingMode == pagingMode
                                    ) {
                                        setPagingMode(pagingMode)
                                    }
                                }
                            }

                            Section("Fit") {
                                ForEach(ReaderFitMode.allCases, id: \.self) { fitMode in
                                    layoutOptionButton(
                                        title: fitMode.title,
                                        isSelected: effectiveReaderLayout.fitMode == fitMode
                                    ) {
                                        setFitMode(fitMode)
                                    }
                                }
                            }

                            if effectiveReaderLayout.pagingMode == .paged {
                                Section("Direction") {
                                    ForEach(ReaderReadingDirection.allCases, id: \.self) { direction in
                                        layoutOptionButton(
                                            title: direction.title,
                                            isSelected: effectiveReaderLayout.readingDirection == direction
                                        ) {
                                            setReadingDirection(direction)
                                        }
                                    }
                                }

                                if supportsDoublePageSpread {
                                    Section("Spread") {
                                        ForEach(ReaderSpreadMode.allCases, id: \.self) { spreadMode in
                                            layoutOptionButton(
                                                title: spreadMode.title,
                                                isSelected: effectiveReaderLayout.spreadMode == spreadMode
                                            ) {
                                                setSpreadMode(spreadMode)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                    }

                    Spacer(minLength: 0)

                    Button(action: presentPageJump) {
                        ReaderChromePill {
                            Text(pageIndicatorText)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        switch document {
        case .pdf(let pdf):
            PDFReaderContainerView(
                document: pdf.pdfDocument,
                requestedPageIndex: currentPageIndex,
                rotation: .degrees0,
                onPageChanged: handleVisiblePageChange(to:),
                onReaderTap: handleReaderTap
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        case .imageSequence(let imageSequence):
            if effectiveReaderLayout.pagingMode == .verticalContinuous {
                VerticalImageSequenceReaderContainerView(
                    document: imageSequence,
                    initialPageIndex: currentPageIndex,
                    layout: effectiveReaderLayout,
                    onPageChanged: handleVisiblePageChange(to:),
                    onReaderTap: handleReaderTap
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            } else {
                ImageSequenceReaderContainerView(
                    document: imageSequence,
                    initialPageIndex: currentPageIndex,
                    layout: effectiveReaderLayout,
                    onPageChanged: handleVisiblePageChange(to:),
                    onReaderTap: handleReaderTap
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            }
        case .unsupported(let document):
            ContentUnavailableView(
                "Unsupported Comic",
                systemImage: "doc.badge.questionmark",
                description: Text(document.reason)
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
        guard readerLayout.pagingMode != pagingMode else {
            return
        }

        var updatedLayout = readerLayout
        updatedLayout.pagingMode = pagingMode
        if pagingMode == .verticalContinuous {
            updatedLayout.spreadMode = .singlePage
        }
        readerSession.updateLayout(updatedLayout)
        persistLayout()
    }

    private func setFitMode(_ fitMode: ReaderFitMode) {
        guard readerLayout.fitMode != fitMode else {
            return
        }

        var updatedLayout = readerLayout
        updatedLayout.fitMode = fitMode
        readerSession.updateLayout(updatedLayout)
        persistLayout()
    }

    private func setReadingDirection(_ readingDirection: ReaderReadingDirection) {
        guard readerLayout.readingDirection != readingDirection else {
            return
        }

        var updatedLayout = readerLayout
        updatedLayout.readingDirection = readingDirection
        readerSession.updateLayout(updatedLayout)
        persistLayout()
    }

    private func setSpreadMode(_ spreadMode: ReaderSpreadMode) {
        guard readerLayout.spreadMode != spreadMode else {
            return
        }

        var updatedLayout = readerLayout
        updatedLayout.spreadMode = spreadMode
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
                transientNoticeMessage = "Remote copy refreshed."
            case .cachedCurrent:
                transientNoticeMessage = "The local copy is already current."
            case .cachedFallback(let message):
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

    @ViewBuilder
    private func layoutOptionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
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
