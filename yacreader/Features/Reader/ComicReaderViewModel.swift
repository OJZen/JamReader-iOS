import Combine
import Foundation

@MainActor
final class ComicReaderViewModel: ObservableObject {
    @Published private(set) var comic: LibraryComic
    @Published private(set) var document: ComicDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var bookmarkPageIndices: [Int]
    @Published private(set) var readerLayout: ReaderDisplayLayout
    @Published private(set) var allowsDoublePageSpread = true
    @Published private(set) var isFavorite: Bool
    @Published private(set) var rating: Int
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor

    private let storageManager: LibraryStorageManager
    private let databaseWriter: LibraryDatabaseWriter
    private let documentLoader: ComicDocumentLoader
    private let readerLayoutPreferencesStore: ReaderLayoutPreferencesStore
    private let onComicUpdated: ((LibraryComic) -> Void)?
    private var navigationContext: ReaderNavigationContext?

    private let databaseURL: URL
    private var accessSession: LibraryAccessSession?
    private var hasLoaded = false
    private var lastPersistedPageIndex: Int?
    private var pendingProgressPersistenceTask: Task<Void, Never>?

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext?,
        storageManager: LibraryStorageManager,
        databaseWriter: LibraryDatabaseWriter,
        documentLoader: ComicDocumentLoader,
        readerLayoutPreferencesStore: ReaderLayoutPreferencesStore,
        onComicUpdated: ((LibraryComic) -> Void)?
    ) {
        self.descriptor = descriptor
        self.comic = comic
        self.storageManager = storageManager
        self.databaseWriter = databaseWriter
        self.documentLoader = documentLoader
        self.readerLayoutPreferencesStore = readerLayoutPreferencesStore
        self.onComicUpdated = onComicUpdated
        self.navigationContext = navigationContext
        self.databaseURL = storageManager.databaseURL(for: descriptor)
        self.bookmarkPageIndices = comic.bookmarkPageIndices.filter { $0 >= 0 }.sorted()
        self.readerLayout = readerLayoutPreferencesStore.loadLayout(for: comic.type)
        self.isFavorite = comic.isFavorite
        self.rating = Self.normalizedRatingValue(from: comic.rating)
    }

    deinit {
        pendingProgressPersistenceTask?.cancel()
    }

    var navigationTitle: String {
        comic.displayTitle
    }

    var pageIndicatorText: String? {
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

    var supportsImageLayoutControls: Bool {
        if let document, case .imageSequence = document {
            return true
        }

        return false
    }

    var supportsRotationControls: Bool {
        guard document != nil else {
            return false
        }

        return effectiveReaderLayout.pagingMode != .verticalContinuous
    }

    var effectiveReaderLayout: ReaderDisplayLayout {
        readerLayout.normalized(allowingDoublePageSpread: allowsDoublePageSpread)
    }

    var currentPageIsBookmarked: Bool {
        bookmarkPageIndices.contains(currentPageIndex)
    }

    var bookmarkItems: [ReaderBookmarkItem] {
        bookmarkPageIndices.map { pageIndex in
            ReaderBookmarkItem(pageIndex: pageIndex, pageNumber: pageIndex + 1)
        }
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
        navigationContext?.previousComic(for: comic.id) != nil
    }

    var canOpenNextComic: Bool {
        navigationContext?.nextComic(for: comic.id) != nil
    }

    var readerContextPositionText: String? {
        navigationContext?.positionText(for: comic.id)
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

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }

            let sourceRootURL = accessSession?.sourceURL ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
            let document = try documentLoader.loadDocument(for: comic, sourceRootURL: sourceRootURL)
            self.document = document
            currentPageIndex = initialPageIndex(for: comic, pageCount: document.pageCount)
            normalizeBookmarks(for: document.pageCount)
            persistProgress(force: true)
        } catch {
            alert = LibraryAlertState(title: "Failed to Open Comic", message: error.localizedDescription)
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
        var updatedBookmarks = bookmarkPageIndices

        if let existingIndex = updatedBookmarks.firstIndex(of: currentPageIndex) {
            updatedBookmarks.remove(at: existingIndex)
        } else {
            updatedBookmarks.append(currentPageIndex)
        }

        applyBookmarks(updatedBookmarks)
    }

    func toggleFavoriteStatus() {
        let updatedValue = !isFavorite

        do {
            try databaseWriter.setFavorite(
                updatedValue,
                for: comic.id,
                in: databaseURL
            )
            publishComicUpdate(comic.updatingFavorite(updatedValue))
        } catch {
            alert = LibraryAlertState(title: "Failed to Update Favorites", message: error.localizedDescription)
        }
    }

    func setRating(_ rating: Int) {
        let normalizedRating = min(max(rating, 0), 5)
        guard self.rating != normalizedRating else {
            return
        }

        let ratingValue = normalizedRating > 0 ? Double(normalizedRating) : nil
        do {
            try databaseWriter.setRating(
                ratingValue,
                for: comic.id,
                in: databaseURL
            )
            publishComicUpdate(comic.updatingRating(ratingValue))
        } catch {
            alert = LibraryAlertState(title: "Failed to Update Rating", message: error.localizedDescription)
        }
    }

    func toggleReadStatus() {
        setReadStatus(!comic.read)
    }

    func setReadStatus(_ isRead: Bool) {
        guard comic.read != isRead else {
            return
        }

        let resolvedPageCount = document?.pageCount

        do {
            try databaseWriter.setReadStatus(
                isRead,
                for: comic.id,
                in: databaseURL
            )

            if let pageCount = resolvedPageCount, pageCount > 0 {
                currentPageIndex = isRead ? (pageCount - 1) : 0
            }

            publishComicUpdate(comic.updatingReadState(
                isRead,
                resolvedPageCount: resolvedPageCount
            ))
            persistProgress(force: true)
        } catch {
            alert = LibraryAlertState(title: "Failed to Update Read Status", message: error.localizedDescription)
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
        let previousType = comic.type
        if updatedComic.type != previousType {
            persistLayoutPreferences(for: previousType)
        }

        publishComicUpdate(updatedComic)
        if updatedComic.type != previousType {
            readerLayout = readerLayoutPreferencesStore.loadLayout(for: updatedComic.type)
        }
    }

    func openPreviousComic() {
        guard let previousComic = navigationContext?.previousComic(for: comic.id) else {
            return
        }

        switchToComic(previousComic)
    }

    func openNextComic() {
        guard let nextComic = navigationContext?.nextComic(for: comic.id) else {
            return
        }

        switchToComic(nextComic)
    }

    private func initialPageIndex(for comic: LibraryComic, pageCount: Int?) -> Int {
        let storedPage = max(1, comic.currentPage)
        let pageIndex = storedPage - 1

        if let pageCount, pageCount > 0 {
            return min(pageIndex, pageCount - 1)
        }

        return max(0, pageIndex)
    }

    private func persistProgress(force: Bool = false) {
        guard document?.pageCount != nil else {
            return
        }

        if !force, lastPersistedPageIndex == currentPageIndex {
            return
        }

        pendingProgressPersistenceTask?.cancel()

        if force {
            writeProgress(for: currentPageIndex)
            return
        }

        let requestedPageIndex = currentPageIndex
        pendingProgressPersistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)

            guard !Task.isCancelled else {
                return
            }

            self?.writeProgress(for: requestedPageIndex)
        }
    }

    private func writeProgress(for pageIndex: Int) {
        guard let pageCount = document?.pageCount else {
            return
        }

        let clampedPageIndex = min(max(pageIndex, 0), max(pageCount - 1, 0))
        guard lastPersistedPageIndex != clampedPageIndex else {
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
            try databaseWriter.updateReadingProgress(
                for: comic.id,
                progress: progress,
                in: databaseURL
            )
            lastPersistedPageIndex = clampedPageIndex
            publishComicUpdate(comic.updatingReadingProgress(progress))
        } catch {
            alert = LibraryAlertState(title: "Failed to Save Progress", message: error.localizedDescription)
        }
    }

    private func switchToComic(_ newComic: LibraryComic) {
        guard !isLoading else {
            return
        }

        persistProgress(force: true)
        persistLayoutPreferences()

        comic = newComic
        document = nil
        currentPageIndex = 0
        bookmarkPageIndices = newComic.bookmarkPageIndices.filter { $0 >= 0 }.sorted()
        readerLayout = readerLayoutPreferencesStore.loadLayout(for: newComic.type)
        isFavorite = newComic.isFavorite
        rating = Self.normalizedRatingValue(from: newComic.rating)
        lastPersistedPageIndex = nil

        load()
    }

    private func updateNavigationContextComic(_ updatedComic: LibraryComic) {
        guard let currentIndex = navigationContext?.currentIndex(for: updatedComic.id) else {
            return
        }

        navigationContext?.comics[currentIndex] = updatedComic
    }

    private func applyBookmarks(_ pageIndices: [Int]) {
        let normalizedBookmarks = Array(
            Set(pageIndices.filter { $0 >= 0 })
        )
        .sorted()
        .prefix(3)

        let bookmarkArray = Array(normalizedBookmarks)
        do {
            try databaseWriter.updateBookmarks(
                for: comic.id,
                bookmarkPageIndices: bookmarkArray,
                in: databaseURL
            )
            bookmarkPageIndices = bookmarkArray
            publishComicUpdate(comic.updatingBookmarkPageIndices(bookmarkArray))
        } catch {
            alert = LibraryAlertState(title: "Failed to Save Bookmarks", message: error.localizedDescription)
        }
    }

    private func normalizeBookmarks(for pageCount: Int?) {
        let filteredBookmarks = bookmarkPageIndices.filter { pageIndex in
            guard pageIndex >= 0 else {
                return false
            }

            if let pageCount {
                return pageIndex < pageCount
            }

            return true
        }

        let normalizedBookmarks = Array(Set(filteredBookmarks)).sorted()
        if normalizedBookmarks != bookmarkPageIndices {
            applyBookmarks(normalizedBookmarks)
        } else {
            bookmarkPageIndices = normalizedBookmarks
        }
    }

    private func persistLayoutPreferences(for type: LibraryFileType? = nil) {
        var persistedLayout = readerLayout
        persistedLayout.rotation = .degrees0
        readerLayoutPreferencesStore.saveLayout(
            persistedLayout,
            for: type ?? comic.type
        )
    }

    private func publishComicUpdate(_ updatedComic: LibraryComic) {
        let didChange = updatedComic != comic
        comic = updatedComic
        isFavorite = updatedComic.isFavorite
        rating = Self.normalizedRatingValue(from: updatedComic.rating)
        updateNavigationContextComic(updatedComic)

        guard didChange else {
            return
        }

        onComicUpdated?(updatedComic)
    }

    private static func normalizedRatingValue(from rating: Double?) -> Int {
        guard let rating, rating > 0 else {
            return 0
        }

        return min(max(Int(rating.rounded()), 0), 5)
    }
}

struct ReaderBookmarkItem: Identifiable, Hashable {
    let pageIndex: Int
    let pageNumber: Int

    var id: Int {
        pageIndex
    }
}
