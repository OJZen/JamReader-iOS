import Foundation

enum RemoteComicOpenMode: Hashable {
    case automatic
    case preferLocalCache
}

enum ComicOpenRequest {
    case library(ComicLibraryOpenRequest)
    case remote(ComicRemoteOpenRequest)
    case file(ComicFileOpenRequest)

    var displayTitle: String {
        switch self {
        case .library(let request):
            return request.comic.displayTitle
        case .remote(let request):
            return request.item.name
        case .file(let request):
            return request.displayName
        }
    }

    var preferredLayoutType: LibraryFileType {
        switch self {
        case .library(let request):
            return request.comic.type
        case .remote, .file:
            return .comic
        }
    }

    var fallbackDocumentURL: URL {
        switch self {
        case .library(let request):
            return URL(fileURLWithPath: request.descriptor.sourcePath, isDirectory: true)
        case .remote(let request):
            return URL(fileURLWithPath: request.item.name)
        case .file(let request):
            return request.fileURL
        }
    }

    var fallbackPageCount: Int {
        switch self {
        case .library(let request):
            return max(request.comic.pageCount ?? max(request.comic.currentPage, 1), 1)
        case .remote(let request):
            return max(request.item.pageCountHint ?? 1, 1)
        case .file:
            return 1
        }
    }

    var fallbackPageIndex: Int {
        switch self {
        case .library(let request):
            return max(request.comic.currentPage - 1, 0)
        case .remote, .file:
            return 0
        }
    }
}

struct ComicLibraryOpenRequest {
    let descriptor: LibraryDescriptor
    let comic: LibraryComic
    let navigationContext: ReaderNavigationContext?
    let onComicUpdated: ((LibraryComic) -> Void)?

    init(
        descriptor: LibraryDescriptor,
        comic: LibraryComic,
        navigationContext: ReaderNavigationContext?,
        onComicUpdated: ((LibraryComic) -> Void)?
    ) {
        self.descriptor = descriptor
        self.comic = comic
        self.navigationContext = navigationContext
        self.onComicUpdated = onComicUpdated
    }
}

struct ComicRemoteOpenRequest {
    let profile: RemoteServerProfile
    let item: RemoteDirectoryItem
    let openMode: RemoteComicOpenMode
    let referenceOverride: RemoteComicFileReference?

    init(
        profile: RemoteServerProfile,
        item: RemoteDirectoryItem,
        openMode: RemoteComicOpenMode,
        referenceOverride: RemoteComicFileReference?
    ) {
        self.profile = profile
        self.item = item
        self.openMode = openMode
        self.referenceOverride = referenceOverride
    }
}

struct ComicFileOpenRequest {
    let fileURL: URL
    let displayName: String

    init(fileURL: URL, displayName: String? = nil) {
        self.fileURL = fileURL
        self.displayName = displayName ?? fileURL.lastPathComponent
    }
}

enum ComicReaderLoadState {
    case idle
    case opening(message: String, progress: Double?)
    case ready(ComicReaderSession, ComicDocument)
    case failed(String)
}

enum ComicOpenEvent {
    case opening(message: String, progress: Double?)
    case ready(ComicReaderSession, ComicDocument)
}

enum ComicReadableSource {
    case file(URL)
    case remoteStreaming(fileName: String, documentURL: URL, reader: any RemoteRandomAccessFileReader)
}

enum ComicReaderStateScope {
    case library(descriptor: LibraryDescriptor, databaseURL: URL, comicID: Int64)
    case remote(profile: RemoteServerProfile, reference: RemoteComicFileReference)
    case transient
}

struct ComicReaderSession {
    let id: String
    let title: String
    let fileName: String
    let source: ComicReadableSource
    let stateScope: ComicReaderStateScope
    let resourceLease: ComicReaderResourceLease
    let fallbackDocumentURL: URL
    let fallbackPageCount: Int
    let initialPageIndex: Int
    let bookmarkPageIndices: [Int]
    let layoutType: LibraryFileType
    let navigationContext: ReaderNavigationContext?
    let libraryComic: LibraryComic?
    let onLibraryComicUpdated: ((LibraryComic) -> Void)?
    let noticeMessage: String?
    let shouldStartBackgroundDownload: Bool

    var isLibraryBacked: Bool {
        if case .library = stateScope {
            return true
        }
        return false
    }

    var remoteContext: (profile: RemoteServerProfile, reference: RemoteComicFileReference)? {
        guard case .remote(let profile, let reference) = stateScope else {
            return nil
        }
        return (profile, reference)
    }
}

final class ComicReaderResourceLease {
    private let libraryAccessSession: LibraryAccessSession?
    private let remoteReaderLease: RemoteReaderCacheLease?
    private let closeLock = NSLock()
    private var hasClosed = false

    init(
        libraryAccessSession: LibraryAccessSession? = nil,
        remoteReaderLease: RemoteReaderCacheLease? = nil
    ) {
        self.libraryAccessSession = libraryAccessSession
        self.remoteReaderLease = remoteReaderLease
    }

    deinit {
        invalidateIfNeeded()
    }

    func close(document: ComicDocument?) async {
        guard markClosed() else {
            return
        }

        if let document,
           case .imageSequence(let imageDocument) = document {
            await imageDocument.pageSource.close()
        }

        remoteReaderLease?.invalidate()
        _ = libraryAccessSession
    }

    private func invalidateIfNeeded() {
        guard markClosed() else {
            return
        }

        remoteReaderLease?.invalidate()
        _ = libraryAccessSession
    }

    private func markClosed() -> Bool {
        closeLock.lock()
        defer { closeLock.unlock() }

        guard !hasClosed else {
            return false
        }

        hasClosed = true
        return true
    }
}

final class RemoteReaderCacheLease {
    private let reference: RemoteComicFileReference
    private let browsingService: RemoteServerBrowsingService
    private let token: UUID
    private let lock = NSLock()
    private var isInvalidated = false

    init(reference: RemoteComicFileReference, browsingService: RemoteServerBrowsingService) {
        self.reference = reference
        self.browsingService = browsingService
        self.token = browsingService.registerActiveReaderLease(for: reference)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        lock.lock()
        guard !isInvalidated else {
            lock.unlock()
            return
        }
        isInvalidated = true
        lock.unlock()
        browsingService.unregisterActiveReaderLease(token, for: reference)
    }
}

struct ComicReaderStateWriteResult {
    let updatedLibraryComic: LibraryComic?
}

final class ComicReaderStateStore {
    private let databaseWriter: LibraryDatabaseWriter
    private let remoteReadingProgressStore: RemoteReadingProgressStore

    init(
        databaseWriter: LibraryDatabaseWriter,
        remoteReadingProgressStore: RemoteReadingProgressStore
    ) {
        self.databaseWriter = databaseWriter
        self.remoteReadingProgressStore = remoteReadingProgressStore
    }

    func saveProgress(
        _ progress: ComicReadingProgress,
        bookmarkPageIndices: [Int],
        session: ComicReaderSession,
        currentLibraryComic: LibraryComic?
    ) throws -> ComicReaderStateWriteResult {
        switch session.stateScope {
        case .library(_, let databaseURL, let comicID):
            try databaseWriter.updateReadingProgress(
                for: comicID,
                progress: progress,
                in: databaseURL
            )
            let updatedComic = currentLibraryComic?.updatingReadingProgress(progress)
            return ComicReaderStateWriteResult(updatedLibraryComic: updatedComic)
        case .remote(let profile, let reference):
            try remoteReadingProgressStore.saveProgress(
                progress,
                for: reference,
                profile: profile,
                bookmarkPageIndices: bookmarkPageIndices
            )
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        case .transient:
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        }
    }

    func saveBookmarks(
        _ bookmarkPageIndices: [Int],
        session: ComicReaderSession,
        currentLibraryComic: LibraryComic?
    ) throws -> ComicReaderStateWriteResult {
        switch session.stateScope {
        case .library(_, let databaseURL, let comicID):
            try databaseWriter.updateBookmarks(
                for: comicID,
                bookmarkPageIndices: bookmarkPageIndices,
                in: databaseURL
            )
            let updatedComic = currentLibraryComic?.updatingBookmarkPageIndices(bookmarkPageIndices)
            return ComicReaderStateWriteResult(updatedLibraryComic: updatedComic)
        case .remote(let profile, let reference):
            let storedProgress = try remoteReadingProgressStore.loadProgress(for: reference)
            let progress = ComicReadingProgress(
                currentPage: max(storedProgress?.currentPage ?? 1, 1),
                pageCount: storedProgress?.pageCount ?? reference.pageCountHint,
                hasBeenOpened: storedProgress?.hasBeenOpened ?? true,
                read: storedProgress?.read ?? false,
                lastTimeOpened: Date()
            )
            try remoteReadingProgressStore.saveProgress(
                progress,
                for: reference,
                profile: profile,
                bookmarkPageIndices: bookmarkPageIndices
            )
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        case .transient:
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        session: ComicReaderSession,
        currentLibraryComic: LibraryComic?
    ) throws -> ComicReaderStateWriteResult {
        guard case .library(_, let databaseURL, let comicID) = session.stateScope else {
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        }

        try databaseWriter.setFavorite(isFavorite, for: comicID, in: databaseURL)
        return ComicReaderStateWriteResult(
            updatedLibraryComic: currentLibraryComic?.updatingFavorite(isFavorite)
        )
    }

    func setRating(
        _ rating: Double?,
        session: ComicReaderSession,
        currentLibraryComic: LibraryComic?
    ) throws -> ComicReaderStateWriteResult {
        guard case .library(_, let databaseURL, let comicID) = session.stateScope else {
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        }

        try databaseWriter.setRating(rating, for: comicID, in: databaseURL)
        return ComicReaderStateWriteResult(
            updatedLibraryComic: currentLibraryComic?.updatingRating(rating)
        )
    }

    func setReadStatus(
        _ isRead: Bool,
        resolvedPageCount: Int?,
        session: ComicReaderSession,
        currentLibraryComic: LibraryComic?
    ) throws -> ComicReaderStateWriteResult {
        guard case .library(_, let databaseURL, let comicID) = session.stateScope else {
            return ComicReaderStateWriteResult(updatedLibraryComic: nil)
        }

        try databaseWriter.setReadStatus(isRead, for: comicID, in: databaseURL)
        return ComicReaderStateWriteResult(
            updatedLibraryComic: currentLibraryComic?.updatingReadState(
                isRead,
                resolvedPageCount: resolvedPageCount
            )
        )
    }
}

final class ComicDocumentService {
    func loadDocument(from source: ComicReadableSource) async throws -> ComicDocument {
        switch source {
        case .file(let fileURL):
            return try await Task.detached(priority: .userInitiated) {
                try ComicDocumentLoader().loadDocument(at: fileURL)
            }.value
        case .remoteStreaming(let fileName, let documentURL, let reader):
            do {
                return try await ComicDocumentLoader().loadRemoteDocument(
                    named: fileName,
                    documentURL: documentURL,
                    reader: reader
                )
            } catch {
                try? await reader.close()
                throw error
            }
        }
    }
}

final class ComicOpenCoordinator {
    private let storageManager: LibraryStorageManager
    private let documentService: ComicDocumentService
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private let remoteReadingProgressStore: RemoteReadingProgressStore

    init(
        storageManager: LibraryStorageManager,
        documentService: ComicDocumentService,
        remoteServerBrowsingService: RemoteServerBrowsingService,
        remoteReadingProgressStore: RemoteReadingProgressStore
    ) {
        self.storageManager = storageManager
        self.documentService = documentService
        self.remoteServerBrowsingService = remoteServerBrowsingService
        self.remoteReadingProgressStore = remoteReadingProgressStore
    }

    func openEvents(for request: ComicOpenRequest) -> AsyncThrowingStream<ComicOpenEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await open(request) { message, progress in
                        continuation.yield(.opening(message: message, progress: progress))
                    }
                    guard !Task.isCancelled else {
                        await result.session.resourceLease.close(document: result.document)
                        continuation.finish()
                        return
                    }
                    continuation.yield(.ready(result.session, result.document))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func open(
        _ request: ComicOpenRequest,
        progress: @escaping @Sendable (String, Double?) -> Void
    ) async throws -> (session: ComicReaderSession, document: ComicDocument) {
        switch request {
        case .library(let request):
            progress("Opening Comic", nil)
            return try await openLibrary(request)
        case .remote(let request):
            return try await openRemote(request, progress: progress)
        case .file(let request):
            progress("Opening Comic", nil)
            return try await openFile(request)
        }
    }

    private func openLibrary(
        _ request: ComicLibraryOpenRequest
    ) async throws -> (session: ComicReaderSession, document: ComicDocument) {
        let accessSession = try storageManager.makeAccessSession(for: request.descriptor)
        let fileURL = Self.resolvedFileURL(for: request.comic, sourceRootURL: accessSession.sourceURL)
        let session = makeLibrarySession(
            request: request,
            source: .file(fileURL),
            lease: ComicReaderResourceLease(libraryAccessSession: accessSession)
        )
        let document = try await documentService.loadDocument(from: session.source)
        return (session.withDocumentDefaults(from: document), document)
    }

    private func openRemote(
        _ request: ComicRemoteOpenRequest,
        progress: @escaping @Sendable (String, Double?) -> Void
    ) async throws -> (session: ComicReaderSession, document: ComicDocument) {
        let reference = try request.referenceOverride
            ?? remoteServerBrowsingService.makeComicFileReference(from: request.item)

        if request.openMode == .preferLocalCache,
           let cachedFileURL = remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
            do {
                return try await openRemoteCachedFile(
                    request: request,
                    reference: reference,
                    cachedFileURL: cachedFileURL,
                    noticeMessage: noticeMessage(for: reference)
                )
            } catch {
                try? remoteServerBrowsingService.clearCachedComic(for: reference)
            }
        }

        let availability = remoteServerBrowsingService.cachedAvailability(for: reference)
        if availability.kind == .current,
           let cachedFileURL = remoteServerBrowsingService.cachedFileURLIfAvailable(for: reference) {
            do {
                return try await openRemoteCachedFile(
                    request: request,
                    reference: reference,
                    cachedFileURL: cachedFileURL,
                    noticeMessage: "Opened the downloaded copy saved on this device."
                )
            } catch {
                try? remoteServerBrowsingService.clearCachedComic(for: reference)
            }
        }

        if await remoteServerBrowsingService.supportsStreamingOpen(for: reference, profile: request.profile),
           ComicDocumentLoader().supportsRemoteStreaming(for: reference.fileName) {
            progress("Preparing Pages", nil)
            let documentURL = remoteServerBrowsingService.plannedCachedFileURL(for: reference)
            let reader = try await remoteServerBrowsingService.makeStreamingFileReader(
                for: request.profile,
                reference: reference
            )
            let lease = ComicReaderResourceLease(
                remoteReaderLease: RemoteReaderCacheLease(
                    reference: reference,
                    browsingService: remoteServerBrowsingService
                )
            )
            let session = makeRemoteSession(
                request: request,
                reference: reference,
                source: .remoteStreaming(
                    fileName: reference.fileName,
                    documentURL: documentURL,
                    reader: reader
                ),
                lease: lease,
                noticeMessage: nil,
                shouldStartBackgroundDownload: true
            )
            let document = try await documentService.loadDocument(from: session.source)
            return (session.withDocumentDefaults(from: document), document)
        }

        progress("Downloading", 0)
        let result = try await remoteServerBrowsingService.downloadComicFile(
            for: request.profile,
            reference: reference,
            progressHandler: { fraction in
                progress("Downloading", fraction)
            }
        )
        let session = makeRemoteSession(
            request: request,
            reference: reference,
            source: .file(result.localFileURL),
            lease: ComicReaderResourceLease(
                remoteReaderLease: RemoteReaderCacheLease(
                    reference: reference,
                    browsingService: remoteServerBrowsingService
                )
            ),
            noticeMessage: noticeMessage(for: result.source),
            shouldStartBackgroundDownload: false
        )
        let document = try await documentService.loadDocument(from: session.source)
        return (session.withDocumentDefaults(from: document), document)
    }

    private func openRemoteCachedFile(
        request: ComicRemoteOpenRequest,
        reference: RemoteComicFileReference,
        cachedFileURL: URL,
        noticeMessage: String?
    ) async throws -> (session: ComicReaderSession, document: ComicDocument) {
        let session = makeRemoteSession(
            request: request,
            reference: reference,
            source: .file(cachedFileURL),
            lease: ComicReaderResourceLease(
                remoteReaderLease: RemoteReaderCacheLease(
                    reference: reference,
                    browsingService: remoteServerBrowsingService
                )
            ),
            noticeMessage: noticeMessage,
            shouldStartBackgroundDownload: false
        )
        let document = try await documentService.loadDocument(from: session.source)
        return (session.withDocumentDefaults(from: document), document)
    }

    private func openFile(
        _ request: ComicFileOpenRequest
    ) async throws -> (session: ComicReaderSession, document: ComicDocument) {
        let session = makeFileSession(request: request)
        let document = try await documentService.loadDocument(from: session.source)
        return (session.withDocumentDefaults(from: document), document)
    }

    private func makeLibrarySession(
        request: ComicLibraryOpenRequest,
        source: ComicReadableSource,
        lease: ComicReaderResourceLease
    ) -> ComicReaderSession {
        let databaseURL = storageManager.databaseURL(for: request.descriptor)
        return ComicReaderSession(
            id: "library:\(request.descriptor.id.uuidString):\(request.comic.id)",
            title: request.comic.displayTitle,
            fileName: request.comic.fileName,
            source: source,
            stateScope: .library(
                descriptor: request.descriptor,
                databaseURL: databaseURL,
                comicID: request.comic.id
            ),
            resourceLease: lease,
            fallbackDocumentURL: URL(fileURLWithPath: request.descriptor.sourcePath, isDirectory: true),
            fallbackPageCount: max(request.comic.pageCount ?? max(request.comic.currentPage, 1), 1),
            initialPageIndex: initialPageIndex(currentPage: request.comic.currentPage, pageCount: request.comic.pageCount),
            bookmarkPageIndices: ReaderBookmarkNormalizer.normalized(
                request.comic.bookmarkPageIndices,
                maximumCount: 3
            ),
            layoutType: request.comic.type,
            navigationContext: request.navigationContext,
            libraryComic: request.comic,
            onLibraryComicUpdated: request.onComicUpdated,
            noticeMessage: nil,
            shouldStartBackgroundDownload: false
        )
    }

    private func makeRemoteSession(
        request: ComicRemoteOpenRequest,
        reference: RemoteComicFileReference,
        source: ComicReadableSource,
        lease: ComicReaderResourceLease,
        noticeMessage: String?,
        shouldStartBackgroundDownload: Bool
    ) -> ComicReaderSession {
        let storedProgress = try? remoteReadingProgressStore.loadProgress(for: reference)
        let initialPageIndex = storedProgress?.pageIndex ?? 0
        return ComicReaderSession(
            id: "remote:\(reference.id)",
            title: request.item.name,
            fileName: reference.fileName,
            source: source,
            stateScope: .remote(profile: request.profile, reference: reference),
            resourceLease: lease,
            fallbackDocumentURL: remoteServerBrowsingService.plannedCachedFileURL(for: reference),
            fallbackPageCount: max(storedProgress?.pageCount ?? reference.pageCountHint ?? 1, 1),
            initialPageIndex: initialPageIndex,
            bookmarkPageIndices: ReaderBookmarkNormalizer.normalized(storedProgress?.bookmarkPageIndices ?? []),
            layoutType: .comic,
            navigationContext: nil,
            libraryComic: nil,
            onLibraryComicUpdated: nil,
            noticeMessage: noticeMessage,
            shouldStartBackgroundDownload: shouldStartBackgroundDownload
        )
    }

    private func makeFileSession(request: ComicFileOpenRequest) -> ComicReaderSession {
        ComicReaderSession(
            id: "file:\(request.fileURL.standardizedFileURL.path)",
            title: request.displayName,
            fileName: request.fileURL.lastPathComponent,
            source: .file(request.fileURL),
            stateScope: .transient,
            resourceLease: ComicReaderResourceLease(),
            fallbackDocumentURL: request.fileURL,
            fallbackPageCount: 1,
            initialPageIndex: 0,
            bookmarkPageIndices: [],
            layoutType: .comic,
            navigationContext: nil,
            libraryComic: nil,
            onLibraryComicUpdated: nil,
            noticeMessage: nil,
            shouldStartBackgroundDownload: false
        )
    }

    private func noticeMessage(for reference: RemoteComicFileReference) -> String? {
        switch remoteServerBrowsingService.cachedAvailability(for: reference).kind {
        case .unavailable:
            return nil
        case .current:
            return "Opened the downloaded copy saved on this device."
        case .stale:
            return "Opened an older downloaded copy saved on this device."
        }
    }

    private func noticeMessage(for source: RemoteComicDownloadResult.Source) -> String? {
        switch source {
        case .downloaded:
            return nil
        case .cachedCurrent:
            return "Opened the downloaded copy saved on this device."
        case .cachedFallback(let message):
            return message
        }
    }

    private func initialPageIndex(currentPage: Int, pageCount: Int?) -> Int {
        let pageIndex = max(currentPage - 1, 0)
        guard let pageCount, pageCount > 0 else {
            return pageIndex
        }
        return min(pageIndex, pageCount - 1)
    }

    private static func resolvedFileURL(for comic: LibraryComic, sourceRootURL: URL) -> URL {
        let rawPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let relativePath = rawPath.isEmpty ? comic.fileName : rawPath
        if relativePath.hasPrefix("/") {
            return sourceRootURL.appendingPathComponent(String(relativePath.dropFirst()))
        }
        return sourceRootURL.appendingPathComponent(relativePath)
    }
}

private extension ComicReaderSession {
    func withDocumentDefaults(from document: ComicDocument) -> ComicReaderSession {
        let pageCount = document.pageCount ?? fallbackPageCount
        return ComicReaderSession(
            id: id,
            title: title,
            fileName: fileName,
            source: source,
            stateScope: stateScope,
            resourceLease: resourceLease,
            fallbackDocumentURL: document.fileURL,
            fallbackPageCount: max(pageCount, 1),
            initialPageIndex: min(initialPageIndex, max(pageCount - 1, 0)),
            bookmarkPageIndices: ReaderBookmarkNormalizer.normalized(
                bookmarkPageIndices,
                pageCount: document.pageCount,
                maximumCount: isLibraryBacked ? 3 : nil
            ),
            layoutType: layoutType,
            navigationContext: navigationContext,
            libraryComic: libraryComic,
            onLibraryComicUpdated: onLibraryComicUpdated,
            noticeMessage: noticeMessage,
            shouldStartBackgroundDownload: shouldStartBackgroundDownload
        )
    }
}
