import Combine
import Foundation

@MainActor
final class ComicReaderViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var loadState: ComicReaderLoadState = .idle
    @Published private(set) var hasAttemptedInitialLoad = false
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var bookmarkPageIndices: [Int] = []
    @Published private(set) var readerLayout: ReaderDisplayLayout
    @Published private(set) var allowsDoublePageSpread = true
    @Published private(set) var isFavorite = false
    @Published private(set) var rating = 0
    @Published private(set) var noticeMessage: String?
    @Published private(set) var backgroundDownloadProgress: Double?
    @Published private(set) var presentedDocument: ComicDocument?
    @Published var alert: AppAlertState?

    private let dependencies: AppDependencies
    private var request: ComicOpenRequest
    private var activeSession: ComicReaderSession?
    private var activeDocument: ComicDocument?
    private var libraryComic: LibraryComic?
    private var navigationContext: ReaderNavigationContext?
    private var hasLoaded = false
    private var currentLoadToken: UUID?
    private var remoteRefreshToken: UUID?
    private var loadTask: Task<Void, Never>?
    private var loadWatchdogTask: Task<Void, Never>?
    private var backgroundDownloadTask: Task<Void, Never>?
    private var noticeDismissalTask: Task<Void, Never>?
    private var lastPersistedProgressSnapshot: ReaderProgressPersistenceSnapshot?
    private var pendingProgressPersistenceTask: Task<Void, Never>?

    init(
        request: ComicOpenRequest,
        dependencies: AppDependencies
    ) {
        self.request = request
        self.dependencies = dependencies
        self.readerLayout = dependencies.readerLayoutPreferencesStore.loadLayout(
            for: request.preferredLayoutType
        )
        self.currentPageIndex = request.fallbackPageIndex
    }

    deinit {
        loadTask?.cancel()
        loadWatchdogTask?.cancel()
        remoteRefreshToken = nil
        backgroundDownloadTask?.cancel()
        noticeDismissalTask?.cancel()
        pendingProgressPersistenceTask?.cancel()

        let session = activeSession
        let document = activeDocument
        Task {
            await session?.resourceLease.close(document: document)
        }
    }

    var navigationTitle: String {
        activeSession?.title ?? request.displayTitle
    }

    var document: ComicDocument? {
        presentedDocument
    }

    var presentedDocumentPublisher: Published<ComicDocument?>.Publisher {
        $presentedDocument
    }

    var documentIdentity: String? {
        guard let document else {
            return nil
        }
        return "\(document.fileURL.path)#\(document.pageCount ?? -1)"
    }

    var isLoading: Bool {
        if case .opening = loadState {
            return true
        }
        return false
    }

    var loadingMessage: String {
        if case .opening(let message, _) = loadState {
            return message
        }
        return "Opening Comic"
    }

    var loadingProgress: Double? {
        if case .opening(_, let progress) = loadState {
            return progress
        }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = loadState {
            return message
        }
        return nil
    }

    var libraryDescriptor: LibraryDescriptor? {
        guard case .library(let descriptor, _, _) = activeSession?.stateScope else {
            if case .library(let request) = request {
                return request.descriptor
            }
            return nil
        }
        return descriptor
    }

    var currentLibraryComic: LibraryComic? {
        libraryComic
    }

    var fileName: String {
        activeSession?.fileName ?? libraryComic?.fileName ?? request.displayTitle
    }

    var fileSeries: String? {
        libraryComic?.series
    }

    var fileVolume: String? {
        libraryComic?.volume
    }

    var fileAddedAt: Date? {
        libraryComic?.addedAt
    }

    var fileLastOpenedAt: Date? {
        libraryComic?.lastOpenedAt
    }

    var fallbackDocumentURL: URL {
        activeSession?.fallbackDocumentURL ?? request.fallbackDocumentURL
    }

    var fallbackPageCount: Int {
        activeSession?.fallbackPageCount ?? request.fallbackPageCount
    }

    var isLibraryBacked: Bool {
        activeSession?.isLibraryBacked ?? {
            if case .library = request {
                return true
            }
            return false
        }()
    }

    var pageIndicatorText: String? {
        ReaderPageIndicatorFormatter.text(
            for: document,
            currentPageIndex: currentPageIndex,
            layout: effectiveReaderLayout
        )
    }

    var supportsImageLayoutControls: Bool {
        if let document, case .imageSequence = document {
            return true
        }
        return false
    }

    var supportsRotationControls: Bool {
        switch document {
        case .pdf?, .imageSequence?:
            return effectiveReaderLayout.pagingMode != .verticalContinuous
        case .ebook?, .unsupported?, nil:
            return false
        }
    }

    var effectiveReaderLayout: ReaderDisplayLayout {
        readerLayout.normalized(allowingDoublePageSpread: allowsDoublePageSpread)
    }

    var currentPageIsBookmarked: Bool {
        bookmarkPageIndices.contains(currentPageIndex)
    }

    var bookmarkItems: [ReaderBookmarkItem] {
        ReaderBookmarkSupport.items(from: bookmarkPageIndices)
    }

    var pageCount: Int? {
        document?.pageCount
    }

    var currentPageNumber: Int? {
        guard let pageCount = document?.pageCount, pageCount > 0 else {
            return nil
        }
        return min(currentPageIndex + 1, pageCount)
    }

    var hasReaderNavigationContext: Bool {
        navigationContext?.comics.count ?? 0 > 1
    }

    var canOpenPreviousComic: Bool {
        guard let libraryComic else {
            return false
        }
        return navigationContext?.previousComic(for: libraryComic.id) != nil
    }

    var canOpenNextComic: Bool {
        guard let libraryComic else {
            return false
        }
        return navigationContext?.nextComic(for: libraryComic.id) != nil
    }

    var readerContextPositionText: String? {
        guard let libraryComic else {
            return nil
        }
        return navigationContext?.positionText(for: libraryComic.id)
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        load()
    }

    func load() {
        guard !isLoading else {
            return
        }

        alert = nil
        loadTask?.cancel()
        loadWatchdogTask?.cancel()
        currentLoadToken = UUID()
        let token = currentLoadToken!
        loadState = .opening(message: "Opening Comic", progress: nil)
        hasAttemptedInitialLoad = true
        startLoadWatchdog(token: token)

        let request = request
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                for try await event in dependencies.comicOpenCoordinator.openEvents(for: request) {
                    guard !Task.isCancelled, currentLoadToken == token else {
                        return
                    }

                    switch event {
                    case .opening(let message, let progress):
                        loadState = .opening(message: message, progress: progress)
                    case .ready(let session, let document):
                        completeOpen(session: session, document: document, token: token)
                    }
                }

                guard !Task.isCancelled, currentLoadToken == token else {
                    return
                }
                failOpen(message: "Opening this comic was canceled.", token: token)
            } catch {
                guard currentLoadToken == token else {
                    return
                }
                failOpen(error, token: token)
            }
        }
    }

    func updateCurrentPage(to pageIndex: Int) {
        guard pageIndex >= 0 else {
            return
        }

        if let pageCount = document?.pageCount, pageCount > 0 {
            currentPageIndex = min(pageIndex, pageCount - 1)
        } else {
            currentPageIndex = pageIndex
        }
        persistProgress()
    }

    func persistCurrentProgress() {
        persistProgress(force: true)
    }

    func setSpreadMode(_ spreadMode: ReaderSpreadMode) {
        guard allowsDoublePageSpread || spreadMode == .singlePage else {
            return
        }
        guard readerLayout.spreadMode != spreadMode else {
            return
        }
        readerLayout.spreadMode = spreadMode
        persistLayoutPreferences()
    }

    func setPagingMode(_ pagingMode: ReaderPagingMode) {
        guard readerLayout.pagingMode != pagingMode else {
            return
        }
        readerLayout.pagingMode = pagingMode
        if pagingMode == .verticalContinuous {
            readerLayout.spreadMode = .singlePage
        }
        persistLayoutPreferences()
    }

    func setAllowsDoublePageSpread(_ allowsDoublePageSpread: Bool) {
        guard self.allowsDoublePageSpread != allowsDoublePageSpread else {
            return
        }
        self.allowsDoublePageSpread = allowsDoublePageSpread
    }

    func setReadingDirection(_ readingDirection: ReaderReadingDirection) {
        guard readerLayout.readingDirection != readingDirection else {
            return
        }
        readerLayout.readingDirection = readingDirection
        persistLayoutPreferences()
    }

    func setFitMode(_ fitMode: ReaderFitMode) {
        guard readerLayout.fitMode != fitMode else {
            return
        }
        readerLayout.fitMode = fitMode
        persistLayoutPreferences()
    }

    func toggleCoverAsSinglePage() {
        readerLayout.coverAsSinglePage.toggle()
        persistLayoutPreferences()
    }

    func setCoverAsSinglePage(_ coverAsSinglePage: Bool) {
        guard readerLayout.coverAsSinglePage != coverAsSinglePage else {
            return
        }
        readerLayout.coverAsSinglePage = coverAsSinglePage
        persistLayoutPreferences()
    }

    func rotateCounterClockwise() {
        readerLayout.rotation = readerLayout.rotation.rotatedCounterClockwise()
    }

    func rotateClockwise() {
        readerLayout.rotation = readerLayout.rotation.rotatedClockwise()
    }

    func resetRotation() {
        readerLayout.rotation = .degrees0
    }

    func toggleBookmarkForCurrentPage() {
        AppHaptics.light()
        applyBookmarks(
            ReaderBookmarkSupport.toggled(
                bookmarkPageIndices,
                at: currentPageIndex,
                pageCount: document?.pageCount,
                maximumCount: isLibraryBacked ? 3 : nil
            )
        )
    }

    func toggleFavoriteStatus() {
        guard let session = activeSession, isLibraryBacked else {
            return
        }
        let updatedValue = !isFavorite
        AppHaptics.medium()

        do {
            let result = try dependencies.comicReaderStateStore.setFavorite(
                updatedValue,
                session: session,
                currentLibraryComic: libraryComic
            )
            applyStateWriteResult(result)
        } catch {
            alert = AppAlertState(title: "Failed to Update Favorites", message: error.userFacingMessage)
        }
    }

    func setRating(_ rating: Int) {
        guard let session = activeSession, isLibraryBacked else {
            return
        }
        let normalizedRating = min(max(rating, 0), 5)
        guard self.rating != normalizedRating else {
            return
        }

        AppHaptics.selection()
        let ratingValue = normalizedRating > 0 ? Double(normalizedRating) : nil
        do {
            let result = try dependencies.comicReaderStateStore.setRating(
                ratingValue,
                session: session,
                currentLibraryComic: libraryComic
            )
            applyStateWriteResult(result)
        } catch {
            alert = AppAlertState(title: "Failed to Update Rating", message: error.userFacingMessage)
        }
    }

    func toggleReadStatus() {
        guard let libraryComic else {
            return
        }
        setReadStatus(!libraryComic.read)
    }

    func setReadStatus(_ isRead: Bool) {
        guard let session = activeSession, isLibraryBacked else {
            return
        }
        guard libraryComic?.read != isRead else {
            return
        }

        AppHaptics.light()
        let resolvedPageCount = document?.pageCount

        do {
            let result = try dependencies.comicReaderStateStore.setReadStatus(
                isRead,
                resolvedPageCount: resolvedPageCount,
                session: session,
                currentLibraryComic: libraryComic
            )
            if let pageCount = resolvedPageCount, pageCount > 0 {
                currentPageIndex = isRead ? (pageCount - 1) : 0
            }
            applyStateWriteResult(result)
            persistProgress(force: true)
        } catch {
            alert = AppAlertState(title: "Failed to Update Read Status", message: error.userFacingMessage)
        }
    }

    func goToBookmark(pageIndex: Int) {
        guard pageIndex >= 0 else {
            return
        }
        if let pageCount = document?.pageCount, pageCount > 0 {
            currentPageIndex = min(pageIndex, pageCount - 1)
        } else {
            currentPageIndex = pageIndex
        }
        persistProgress()
    }

    func goToPage(number: Int) {
        guard let pageCount = document?.pageCount, (1...pageCount).contains(number) else {
            return
        }
        currentPageIndex = number - 1
        persistProgress(force: true)
    }

    func applyUpdatedComic(_ updatedComic: LibraryComic) {
        let previousType = libraryComic?.type
        if let previousType, updatedComic.type != previousType {
            persistLayoutPreferences(for: previousType)
        }

        publishLibraryComicUpdate(updatedComic)
        if updatedComic.type != previousType {
            readerLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: updatedComic.type)
        }
    }

    func openPreviousComic() {
        guard let libraryComic,
              let previousComic = navigationContext?.previousComic(for: libraryComic.id) else {
            return
        }
        switchToLibraryComic(previousComic)
    }

    func openNextComic() {
        guard let libraryComic,
              let nextComic = navigationContext?.nextComic(for: libraryComic.id) else {
            return
        }
        switchToLibraryComic(nextComic)
    }

    func refreshRemoteCopy() {
        guard let session = activeSession,
              let context = session.remoteContext,
              backgroundDownloadTask == nil else {
            return
        }

        let token = UUID()
        remoteRefreshToken = token
        backgroundDownloadProgress = 0
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                dependencies.remoteServerBrowsingService.unregisterAutomaticCacheTask(for: context.reference)
                Task { @MainActor in
                    if self.remoteRefreshToken == token {
                        self.remoteRefreshToken = nil
                    }
                    self.backgroundDownloadTask = nil
                    self.backgroundDownloadProgress = nil
                }
            }

            do {
                let result = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                    for: context.profile,
                    reference: context.reference,
                    forceRefresh: true,
                    progressHandler: { progress in
                        Task { @MainActor in
                            guard self.remoteRefreshToken == token else {
                                return
                            }
                            self.backgroundDownloadProgress = progress
                        }
                    }
                )
                guard !Task.isCancelled, remoteRefreshToken == token else {
                    return
                }
                noticeMessage = noticeMessage(for: result.source)
                scheduleNoticeDismissalIfNeeded()
            } catch {
                guard !Task.isCancelled, remoteRefreshToken == token else {
                    return
                }
                alert = AppAlertState(
                    title: "Failed to Refresh Remote Comic",
                    message: error.userFacingMessage
                )
            }
        }
        backgroundDownloadTask = task
        dependencies.remoteServerBrowsingService.registerAutomaticCacheTask(
            for: context.reference,
            cancellation: { [task] in task.cancel() }
        )
    }

    private func completeOpen(session: ComicReaderSession, document: ComicDocument, token: UUID) {
        guard currentLoadToken == token else {
            Task {
                await session.resourceLease.close(document: document)
            }
            return
        }

        loadWatchdogTask?.cancel()
        loadTask = nil
        currentLoadToken = nil
        applyReadySession(session, document: document, replacingCurrentDocument: true)
        persistProgress()
        startBackgroundDownloadIfNeeded(for: session)
    }

    private func failOpen(_ error: Error, token: UUID) {
        failOpen(message: error.userFacingMessage, token: token)
    }

    private func failOpen(message: String, token: UUID) {
        guard currentLoadToken == token else {
            return
        }
        loadWatchdogTask?.cancel()
        loadTask = nil
        currentLoadToken = nil
        loadState = .failed(message)
        alert = AppAlertState(title: "Failed to Open Comic", message: message)
    }

    private func applyReadySession(
        _ session: ComicReaderSession,
        document: ComicDocument,
        replacingCurrentDocument: Bool
    ) {
        let previousSession = activeSession
        let previousDocument = activeDocument
        let isReplacingSession = replacingCurrentDocument && previousSession?.id != session.id

        if isReplacingSession {
            backgroundDownloadTask?.cancel()
            backgroundDownloadTask = nil
            backgroundDownloadProgress = nil
            remoteRefreshToken = nil
        }

        activeSession = session
        activeDocument = document
        currentPageIndex = session.initialPageIndex
        bookmarkPageIndices = session.bookmarkPageIndices
        readerLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: session.layoutType)
        libraryComic = session.libraryComic
        navigationContext = session.navigationContext
        isFavorite = session.libraryComic?.isFavorite ?? false
        rating = Self.normalizedRatingValue(from: session.libraryComic?.rating)
        noticeMessage = session.noticeMessage
        hasAttemptedInitialLoad = true
        presentedDocument = document
        loadState = .ready(session, document)
        normalizeBookmarks(for: document.pageCount)
        scheduleNoticeDismissalIfNeeded()

        if isReplacingSession {
            Task {
                await previousSession?.resourceLease.close(document: previousDocument)
            }
        }
    }

    private func startLoadWatchdog(token: UUID) {
        loadWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            guard self?.currentLoadToken == token else {
                return
            }
            self?.loadTask?.cancel()
            self?.loadTask = nil
            self?.currentLoadToken = nil
            self?.loadState = .failed("Opening this comic took too long.")
            self?.alert = AppAlertState(
                title: "Failed to Open Comic",
                message: "Opening this comic took too long. The file may be unavailable or the storage provider is not responding."
            )
        }
    }

    private func startBackgroundDownloadIfNeeded(for session: ComicReaderSession) {
        guard session.shouldStartBackgroundDownload,
              let context = session.remoteContext,
              backgroundDownloadTask == nil else {
            return
        }

        backgroundDownloadProgress = 0
        let sessionID = session.id
        let task = Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            defer {
                dependencies.remoteServerBrowsingService.unregisterAutomaticCacheTask(for: context.reference)
                Task { @MainActor in
                    guard self.activeSession?.id == sessionID else {
                        return
                    }
                    self.backgroundDownloadTask = nil
                    self.backgroundDownloadProgress = nil
                }
            }

            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else {
                return
            }

            do {
                _ = try await dependencies.remoteServerBrowsingService.downloadComicFile(
                    for: context.profile,
                    reference: context.reference,
                    progressHandler: { progress in
                        Task { @MainActor in
                            guard self.activeSession?.id == sessionID else {
                                return
                            }
                            self.backgroundDownloadProgress = progress
                        }
                    }
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self.activeSession?.id == sessionID else {
                        return
                    }
                    self.noticeMessage = "Offline copy ready."
                    self.scheduleNoticeDismissalIfNeeded()
                }
            } catch {
                await MainActor.run {
                    guard self.activeSession?.id == sessionID else {
                        return
                    }
                    self.backgroundDownloadProgress = nil
                }
            }
        }

        backgroundDownloadTask = task
        dependencies.remoteServerBrowsingService.registerAutomaticCacheTask(
            for: context.reference,
            cancellation: { task.cancel() }
        )
    }

    private func persistProgress(force: Bool = false) {
        guard let session = activeSession, let document else {
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
            writeProgress(for: requestedSnapshot, session: session, document: document)
            return
        }

        pendingProgressPersistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.writeProgress(for: requestedSnapshot, session: session, document: document)
        }
    }

    private func writeProgress(
        for snapshot: ReaderProgressPersistenceSnapshot,
        session: ComicReaderSession,
        document: ComicDocument
    ) {
        guard activeSession?.id == session.id else {
            return
        }
        guard lastPersistedProgressSnapshot != snapshot else {
            return
        }

        let progress = readingProgress(for: snapshot, document: document)

        do {
            let result = try dependencies.comicReaderStateStore.saveProgress(
                progress,
                bookmarkPageIndices: snapshot.bookmarkPageIndices,
                session: session,
                currentLibraryComic: libraryComic
            )
            lastPersistedProgressSnapshot = snapshot
            applyStateWriteResult(result)
        } catch {
            alert = AppAlertState(title: "Failed to Save Progress", message: error.userFacingMessage)
        }
    }

    private func progressSnapshot(for document: ComicDocument) -> ReaderProgressPersistenceSnapshot {
        let snapshotPageCount = max(document.pageCount ?? 1, 1)
        return ReaderProgressFactory.snapshot(
            pageIndex: currentPageIndex,
            pageCount: snapshotPageCount,
            bookmarkPageIndices: bookmarkPageIndices,
            maximumBookmarkCount: isLibraryBacked ? 3 : nil
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

    private func switchToLibraryComic(_ newComic: LibraryComic) {
        guard !isLoading,
              let descriptor = libraryDescriptor else {
            return
        }

        persistProgress(force: true)
        persistLayoutPreferences()

        let previousSession = activeSession
        let previousDocument = activeDocument
        Task {
            await previousSession?.resourceLease.close(document: previousDocument)
        }

        let nextRequest = ComicOpenRequest.library(
            ComicLibraryOpenRequest(
                descriptor: descriptor,
                comic: newComic,
                navigationContext: navigationContext,
                onComicUpdated: activeSession?.onLibraryComicUpdated
            )
        )
        request = nextRequest
        activeSession = nil
        activeDocument = nil
        presentedDocument = nil
        libraryComic = newComic
        currentPageIndex = max(newComic.currentPage - 1, 0)
        bookmarkPageIndices = ReaderBookmarkNormalizer.normalized(
            newComic.bookmarkPageIndices,
            maximumCount: 3
        )
        readerLayout = dependencies.readerLayoutPreferencesStore.loadLayout(for: newComic.type)
        isFavorite = newComic.isFavorite
        rating = Self.normalizedRatingValue(from: newComic.rating)
        lastPersistedProgressSnapshot = nil
        hasLoaded = true
        load()
    }

    private func applyBookmarks(_ pageIndices: [Int]) {
        let bookmarkArray = ReaderBookmarkNormalizer.normalized(
            pageIndices,
            pageCount: document?.pageCount,
            maximumCount: isLibraryBacked ? 3 : nil
        )
        bookmarkPageIndices = bookmarkArray

        guard let session = activeSession else {
            return
        }

        if isLibraryBacked {
            do {
                let result = try dependencies.comicReaderStateStore.saveBookmarks(
                    bookmarkArray,
                    session: session,
                    currentLibraryComic: libraryComic
                )
                applyStateWriteResult(result)
            } catch {
                alert = AppAlertState(title: "Failed to Save Bookmarks", message: error.userFacingMessage)
            }
        } else {
            persistProgress(force: true)
        }
    }

    private func normalizeBookmarks(for pageCount: Int?) {
        let normalizedBookmarks = ReaderBookmarkNormalizer.normalized(
            bookmarkPageIndices,
            pageCount: pageCount,
            maximumCount: isLibraryBacked ? 3 : nil
        )
        if normalizedBookmarks != bookmarkPageIndices {
            applyBookmarks(normalizedBookmarks)
        }
    }

    private func persistLayoutPreferences(for type: LibraryFileType? = nil) {
        var persistedLayout = readerLayout
        persistedLayout.rotation = .degrees0
        dependencies.readerLayoutPreferencesStore.saveLayout(
            persistedLayout,
            for: type ?? activeSession?.layoutType ?? request.preferredLayoutType
        )
    }

    private func applyStateWriteResult(_ result: ComicReaderStateWriteResult) {
        guard let updatedComic = result.updatedLibraryComic else {
            return
        }
        publishLibraryComicUpdate(updatedComic)
    }

    private func publishLibraryComicUpdate(_ updatedComic: LibraryComic) {
        let didChange = updatedComic != libraryComic
        libraryComic = updatedComic
        isFavorite = updatedComic.isFavorite
        rating = Self.normalizedRatingValue(from: updatedComic.rating)
        updateNavigationContextComic(updatedComic)

        guard didChange else {
            return
        }

        activeSession?.onLibraryComicUpdated?(updatedComic)
    }

    private func updateNavigationContextComic(_ updatedComic: LibraryComic) {
        guard let currentIndex = navigationContext?.currentIndex(for: updatedComic.id) else {
            return
        }
        navigationContext?.comics[currentIndex] = updatedComic
    }

    private func noticeMessage(for source: RemoteComicDownloadResult.Source) -> String? {
        switch source {
        case .downloaded:
            return "Remote copy refreshed."
        case .cachedCurrent:
            return "The local copy is already current."
        case .cachedFallback(let message):
            return message
        }
    }

    private func scheduleNoticeDismissalIfNeeded() {
        noticeDismissalTask?.cancel()
        guard noticeMessage != nil else {
            return
        }

        noticeDismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.noticeMessage = nil
        }
    }

    private static func normalizedRatingValue(from rating: Double?) -> Int {
        guard let rating, rating > 0 else {
            return 0
        }
        return min(max(Int(rating.rounded()), 0), 5)
    }
}
