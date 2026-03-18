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

    @State private var document: ComicDocument?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var isRefreshingRemoteCopy = false
    @State private var isShowingPageJumpSheet = false
    @State private var isShowingThumbnailBrowser = false
    @State private var currentPageIndex = 0
    @State private var pendingPageNumberText = ""
    @State private var bookmarkPageIndices: [Int]
    @State private var readerLayout: ReaderDisplayLayout
    @State private var isReaderChromeHidden = true
    @State private var alert: RemoteAlertState?
    @State private var lastPersistedPageIndex: Int?
    @State private var lastPersistedBookmarkPageIndices: [Int]
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
        _currentPageIndex = State(initialValue: Self.initialPageIndex(from: storedProgress))
        _transientNoticeMessage = State(initialValue: noticeMessage)
        _bookmarkPageIndices = State(initialValue: Self.normalizedBookmarkPageIndices(storedProgress?.bookmarkPageIndices ?? []))
        _lastPersistedBookmarkPageIndices = State(initialValue: [])
        _readerLayout = State(
            initialValue: dependencies.readerLayoutPreferencesStore.loadLayout(for: .comic)
        )
    }

    var body: some View {
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
        .overlay {
            readerChromeOverlay
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if isRefreshingRemoteCopy {
                    ProgressView("Refreshing Remote Copy")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                if let transientNoticeMessage {
                    Text(transientNoticeMessage)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)
        }
        .task {
            await loadIfNeeded()
            updateIdleTimerState()
        }
        .onAppear {
            updateIdleTimerState()
            scheduleNoticeDismissalIfNeeded()
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
        }
        .onChange(of: currentPageIndex) { _, _ in
            persistProgress()
        }
        .sheet(isPresented: $isShowingPageJumpSheet) {
            RemoteReaderPageJumpSheet(
                pageNumberText: $pendingPageNumberText,
                currentPageNumber: currentPageNumber ?? 1,
                pageCount: document?.pageCount ?? 1,
                onCancel: dismissPageJump,
                onJump: submitPageJump
            )
        }
        .sheet(isPresented: $isShowingThumbnailBrowser) {
            if let document {
                ReaderThumbnailBrowserSheet(
                    document: document,
                    currentPageIndex: currentPageIndex
                ) { pageIndex in
                    updateCurrentPage(to: pageIndex)
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
        bookmarkPageIndices.map { pageIndex in
            ReaderBookmarkItem(pageIndex: pageIndex, pageNumber: pageIndex + 1)
        }
    }

    private var pageIndicatorText: String? {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return nil
        }

        guard let document, case .imageSequence = document else {
            return "\(min(currentPageIndex + 1, pageCount)) / \(pageCount)"
        }

        let spreads = ReaderSpreadDescriptor.makeSpreads(pageCount: pageCount, layout: effectiveReaderLayout)
        guard let spreadIndex = ReaderSpreadDescriptor.spreadIndex(containing: currentPageIndex, in: spreads),
              spreads.indices.contains(spreadIndex)
        else {
            return "\(min(currentPageIndex + 1, pageCount)) / \(pageCount)"
        }

        let visiblePages = spreads[spreadIndex].pageIndices.map { $0 + 1 }
        if visiblePages.count == 2, let firstPage = visiblePages.first, let lastPage = visiblePages.last {
            return "\(firstPage)-\(lastPage) / \(pageCount)"
        }

        return "\(visiblePages.first ?? min(currentPageIndex + 1, pageCount)) / \(pageCount)"
    }

    @ViewBuilder
    private var readerChromeOverlay: some View {
        ReaderChromeOverlay(isHidden: isReaderChromeHidden) {
            ReaderChromeBar {
                HStack(spacing: 12) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "chevron.backward")
                            .font(.headline.weight(.semibold))
                    }

                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 0)

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
        } bottomBar: {
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
                                            updateCurrentPage(to: bookmark.pageIndex)
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
    }

    @ViewBuilder
    private func readerContent(for document: ComicDocument) -> some View {
        switch document {
        case .pdf(let pdf):
            PDFReaderContainerView(
                document: pdf.pdfDocument,
                requestedPageIndex: currentPageIndex,
                rotation: .degrees0,
                onPageChanged: { pageIndex in
                    currentPageIndex = pageIndex
                },
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
                    onPageChanged: { pageIndex in
                        currentPageIndex = pageIndex
                    },
                    onReaderTap: handleReaderTap
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            } else {
                ImageSequenceReaderContainerView(
                    document: imageSequence,
                    initialPageIndex: currentPageIndex,
                    layout: effectiveReaderLayout,
                    onPageChanged: { pageIndex in
                        currentPageIndex = pageIndex
                    },
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
            currentPageIndex = initialPageIndex(for: loadedDocument.pageCount)
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
        withAnimation(.easeInOut(duration: 0.2)) {
            switch region {
            case .center, .leading, .trailing:
                isReaderChromeHidden.toggle()
            }
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
            currentPageIndex = min(pageIndex, pageCount - 1)
        } else {
            currentPageIndex = pageIndex
        }
    }

    private func toggleBookmark() {
        var updatedBookmarks = bookmarkPageIndices
        if let existingIndex = updatedBookmarks.firstIndex(of: currentPageIndex) {
            updatedBookmarks.remove(at: existingIndex)
        } else {
            updatedBookmarks.append(currentPageIndex)
        }

        bookmarkPageIndices = Self.normalizedBookmarkPageIndices(updatedBookmarks)
        persistProgress(force: true)
    }

    private func presentPageJump() {
        guard let currentPageNumber else {
            return
        }

        pendingPageNumberText = "\(currentPageNumber)"
        isShowingPageJumpSheet = true
    }

    private func dismissPageJump() {
        isShowingPageJumpSheet = false
    }

    private func submitPageJump() {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return
        }

        let trimmedValue = pendingPageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageNumber = Int(trimmedValue), (1...pageCount).contains(pageNumber) else {
            alert = RemoteAlertState(
                title: "Invalid Page Number",
                message: "Enter a page between 1 and \(pageCount)."
            )
            return
        }

        updateCurrentPage(to: pageNumber - 1)
        isShowingPageJumpSheet = false
        persistProgress(force: true)
    }

    private func setPagingMode(_ pagingMode: ReaderPagingMode) {
        guard readerLayout.pagingMode != pagingMode else {
            return
        }

        readerLayout.pagingMode = pagingMode
        if pagingMode == .verticalContinuous {
            readerLayout.spreadMode = .singlePage
        }
        persistLayout()
    }

    private func setFitMode(_ fitMode: ReaderFitMode) {
        guard readerLayout.fitMode != fitMode else {
            return
        }

        readerLayout.fitMode = fitMode
        persistLayout()
    }

    private func setReadingDirection(_ readingDirection: ReaderReadingDirection) {
        guard readerLayout.readingDirection != readingDirection else {
            return
        }

        readerLayout.readingDirection = readingDirection
        persistLayout()
    }

    private func setSpreadMode(_ spreadMode: ReaderSpreadMode) {
        guard readerLayout.spreadMode != spreadMode else {
            return
        }

        readerLayout.spreadMode = spreadMode
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
        guard document?.pageCount != nil else {
            return
        }

        if !force,
           lastPersistedPageIndex == currentPageIndex,
           lastPersistedBookmarkPageIndices == bookmarkPageIndices {
            return
        }

        pendingProgressPersistenceTask?.cancel()

        if force {
            writeProgress(for: currentPageIndex, bookmarkPageIndices: bookmarkPageIndices)
            return
        }

        let requestedPageIndex = currentPageIndex
        let requestedBookmarkPageIndices = bookmarkPageIndices
        pendingProgressPersistenceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                writeProgress(for: requestedPageIndex, bookmarkPageIndices: requestedBookmarkPageIndices)
            }
        }
    }

    private func writeProgress(for pageIndex: Int, bookmarkPageIndices: [Int]) {
        guard let pageCount = document?.pageCount else {
            return
        }

        let clampedPageIndex = min(max(pageIndex, 0), max(pageCount - 1, 0))
        let normalizedBookmarks = Self.normalizedBookmarkPageIndices(bookmarkPageIndices)
            .filter { $0 < pageCount }
        guard lastPersistedPageIndex != clampedPageIndex
                || lastPersistedBookmarkPageIndices != normalizedBookmarks
        else {
            return
        }

        let currentPage = max(1, clampedPageIndex + 1)
        let progress = ComicReadingProgress(
            currentPage: currentPage,
            pageCount: pageCount,
            hasBeenOpened: true,
            read: currentPage >= pageCount,
            lastTimeOpened: Date()
        )

        do {
            try dependencies.remoteReadingProgressStore.saveProgress(
                progress,
                for: reference,
                profile: profile,
                bookmarkPageIndices: normalizedBookmarks
            )
            lastPersistedPageIndex = clampedPageIndex
            lastPersistedBookmarkPageIndices = normalizedBookmarks
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
            updateCurrentPage(to: min(preservedPageIndex, max((loadedDocument.pageCount ?? 1) - 1, 0)))
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

    private func normalizeBookmarks(for pageCount: Int?) {
        guard let pageCount, pageCount > 0 else {
            bookmarkPageIndices = Self.normalizedBookmarkPageIndices(bookmarkPageIndices)
            return
        }

        let normalizedBookmarks = Self.normalizedBookmarkPageIndices(bookmarkPageIndices)
            .filter { $0 < pageCount }
        if normalizedBookmarks != bookmarkPageIndices {
            bookmarkPageIndices = normalizedBookmarks
        }
    }

    private static func normalizedBookmarkPageIndices(_ pageIndices: [Int]) -> [Int] {
        Array(Set(pageIndices.filter { $0 >= 0 })).sorted()
    }
}

private struct RemoteReaderPageJumpSheet: View {
    @Binding var pageNumberText: String

    let currentPageNumber: Int
    let pageCount: Int
    let onCancel: () -> Void
    let onJump: () -> Void

    @FocusState private var isFocused: Bool

    private var isValidPageNumber: Bool {
        guard let pageNumber = Int(pageNumberText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        return (1...pageCount).contains(pageNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("Page number", text: $pageNumberText)
                        .keyboardType(.numberPad)
                        .focused($isFocused)

                    Text("Current page: \(currentPageNumber)")
                        .foregroundStyle(.secondary)

                    Text("Valid range: 1-\(pageCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Go to Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump", action: onJump)
                        .disabled(!isValidPageNumber)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
    }
}
