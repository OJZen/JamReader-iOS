import Combine
import Foundation
import UIKit

@MainActor
final class LibraryBrowserViewModel: ObservableObject, LoadableViewModel {
    @Published private(set) var content: LibraryFolderContent?
    @Published private(set) var isLoading = false
    @Published private(set) var isInitializingLibrary = false
    @Published private(set) var isRefreshingLibrary = false
    @Published private(set) var isSearching = false
    @Published private(set) var emptyStateMessage: String?
    @Published private(set) var lastInitializationSummary: LibraryScanSummary?
    @Published private(set) var maintenanceRecord: LibraryMaintenanceRecord?
    @Published private(set) var scanProgress: LibraryScanProgress?
    @Published private(set) var scanCompletion: LibraryScanCompletionState?
    @Published private(set) var searchResults: LibrarySearchResults?
    @Published private(set) var continueReadingComics: [LibraryComic] = []
    @Published private(set) var recentComics: [LibraryComic] = []
    @Published private(set) var favoritesComics: [LibraryComic] = []
    @Published private(set) var specialCollectionCounts: [LibrarySpecialCollectionKind: Int] = [:]
    @Published var searchQuery = ""
    @Published var alert: LibraryAlertState?

    let descriptor: LibraryDescriptor
    private(set) var folderID: Int64

    private let storageManager: LibraryStorageManager
    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: LibraryScanner
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let coverLocator: LibraryCoverLocator
    private let comicInfoImportService: ComicInfoImportService
    private let importedComicsImportService: ImportedComicsImportService
    private let comicRemovalService: LibraryComicRemovalService
    private let databaseInspector = SQLiteDatabaseInspector()

    private let metadataRootURL: URL
    private let databaseURL: URL
    private var activeSearchToken = UUID()
    private var accessSession: LibraryAccessSession?
    private var cancellables = Set<AnyCancellable>()
    private var scanCompletionDismissTask: Task<Void, Never>?
    private var hasLoaded = false
    private let previewCollectionLimit = 6
    private static let searchResultLimit = 40
    private var recentDays = LibraryRecentWindowOption.defaultOption.dayCount
    private let supportedImportedFileExtensions: Set<String> = [
        "cbr", "cbz", "rar", "zip", "tar", "7z", "cb7", "arj", "cbt", "pdf"
    ]

    init(
        descriptor: LibraryDescriptor,
        folderID: Int64 = 1,
        storageManager: LibraryStorageManager,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: LibraryScanner,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        coverLocator: LibraryCoverLocator,
        comicInfoImportService: ComicInfoImportService,
        importedComicsImportService: ImportedComicsImportService,
        comicRemovalService: LibraryComicRemovalService
    ) {
        self.descriptor = descriptor
        self.folderID = folderID
        self.storageManager = storageManager
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        self.databaseBootstrapper = databaseBootstrapper
        self.libraryScanner = libraryScanner
        self.maintenanceStatusStore = maintenanceStatusStore
        self.coverLocator = coverLocator
        self.comicInfoImportService = comicInfoImportService
        self.importedComicsImportService = importedComicsImportService
        self.comicRemovalService = comicRemovalService
        self.metadataRootURL = storageManager.metadataRootURL(for: descriptor)
        self.databaseURL = storageManager.databaseURL(for: descriptor)
        let initialMaintenanceRecord = maintenanceStatusStore.loadRecord(for: descriptor.id)
        self.maintenanceRecord = initialMaintenanceRecord
        self.lastInitializationSummary = initialMaintenanceRecord?.summary
        self.databaseSummary = SQLiteDatabaseInspector().inspectDatabase(at: self.databaseURL)
        configureSearch()
    }

    @Published private(set) var databaseSummary: LibraryDatabaseSummary

    var navigationTitle: String {
        if let content {
            return content.folder.isRoot ? descriptor.name : content.folder.displayName
        }

        return descriptor.name
    }

    var folderPath: String {
        content?.folder.path ?? descriptor.sourcePath
    }

    var databasePath: String {
        databaseURL.path
    }

    var canInitializeLibrary: Bool {
        content == nil && !databaseExists && folderID == 1
    }

    var canRefreshLibrary: Bool {
        folderID == 1
            && databaseExists
            && databaseSummary.hasCompatibleSchemaVersion
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canRefreshCurrentFolder: Bool {
        folderID != 1
            && content != nil
            && databaseExists
            && databaseSummary.hasCompatibleSchemaVersion
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canScanFromCurrentContext: Bool {
        canRefreshLibrary || canRefreshCurrentFolder
    }

    var canImportLibraryComicInfo: Bool {
        folderID == 1
            && databaseExists
            && databaseSummary.hasCompatibleSchemaVersion
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canImportCurrentFolderComicInfo: Bool {
        folderID != 1
            && content != nil
            && databaseExists
            && databaseSummary.hasCompatibleSchemaVersion
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canImportComicFiles: Bool {
        content != nil
            && databaseExists
            && databaseSummary.hasCompatibleSchemaVersion
            && supportsDirectLibraryImports
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var libraryImportCompatibilityNotice: String? {
        switch importedComicsImportService.importAvailability(for: descriptor) {
        case .available:
            return nil
        case .unavailable(let message):
            return message
        }
    }

    var compatibilityPresentation: LibraryCompatibilityPresentation? {
        let availability = importedComicsImportService.importAvailability(for: descriptor)
        let presentation = LibraryCompatibilityPresentation.resolve(
            descriptor: descriptor,
            availability: availability
        )

        return presentation.bannerTitle == nil ? nil : presentation
    }

    var supportsDirectLibraryImports: Bool {
        importedComicsImportService.importAvailability(for: descriptor).isSelectable
    }

    var canRemoveComics: Bool {
        comicRemovalService.canRemoveComics(from: descriptor)
    }

    var hasActiveSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var continueReadingComic: LibraryComic? {
        continueReadingComics.first
    }

    var recentPreviewComics: [LibraryComic] {
        Array(recentComics.prefix(previewCollectionLimit))
    }

    var favoritesPreviewComics: [LibraryComic] {
        Array(favoritesComics.prefix(previewCollectionLimit))
    }

    var currentRecentDays: Int {
        recentDays
    }

    func specialCollectionCount(for kind: LibrarySpecialCollectionKind) -> Int {
        if let count = specialCollectionCounts[kind] {
            return count
        }

        switch kind {
        case .reading:
            return continueReadingComics.count
        case .favorites:
            return favoritesComics.count
        case .recent:
            return recentComics.count
        }
    }

    func applyUpdatedComic(_ updatedComic: LibraryComic) {
        let previousComic = existingComicSnapshot(for: updatedComic.id)

        if let content {
            let updatedComics = content.comics.map { comic in
                comic.id == updatedComic.id ? updatedComic : comic
            }

            if updatedComics != content.comics {
                self.content = LibraryFolderContent(
                    folder: content.folder,
                    subfolders: content.subfolders,
                    comics: updatedComics
                )
            }
        }

        if !continueReadingComics.isEmpty {
            continueReadingComics = continueReadingComics.compactMap { comic in
                let resolvedComic = comic.id == updatedComic.id ? updatedComic : comic
                return resolvedComic.isContinueReadingCandidate ? resolvedComic : nil
            }
        }

        if !recentComics.isEmpty {
            recentComics = recentComics.compactMap { comic in
                let resolvedComic = comic.id == updatedComic.id ? updatedComic : comic
                return resolvedComic.belongs(
                    to: .recent,
                    recentDays: recentDays
                ) ? resolvedComic : nil
            }
        }

        if folderID == 1 {
            favoritesComics = favoritesComics.compactMap { comic in
                let resolvedComic = comic.id == updatedComic.id ? updatedComic : comic
                return resolvedComic.isFavorite ? resolvedComic : nil
            }

            if updatedComic.isFavorite, !favoritesComics.contains(where: { $0.id == updatedComic.id }) {
                favoritesComics.insert(updatedComic, at: 0)
            }
        }

        if let searchResults {
            self.searchResults = LibrarySearchResults(
                query: searchResults.query,
                folders: searchResults.folders,
                comics: searchResults.comics.map { comic in
                    comic.id == updatedComic.id ? updatedComic : comic
                }
            )
        }

        refreshSpecialCollectionCountsLocally(
            previous: previousComic,
            updated: updatedComic
        )
    }

    func toggleFavorite(for comic: LibraryComic) {
        let updatedValue = !comic.isFavorite
        AppHaptics.medium()

        do {
            try databaseWriter.setFavorite(
                updatedValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingFavorite(updatedValue))
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Favorites",
                message: error.localizedDescription
            )
        }
    }

    func toggleReadStatus(for comic: LibraryComic) {
        let updatedValue = !comic.read
        AppHaptics.light()

        do {
            try databaseWriter.setReadStatus(
                updatedValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingReadState(updatedValue))
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Read Status",
                message: error.localizedDescription
            )
        }
    }

    func setRating(_ rating: Int, for comic: LibraryComic) {
        let normalizedRating = min(max(rating, 0), 5)
        let ratingValue = normalizedRating > 0 ? Double(normalizedRating) : nil
        let currentRating = min(max(Int((comic.rating ?? 0).rounded()), 0), 5)
        guard currentRating != normalizedRating else {
            return
        }

        AppHaptics.selection()

        do {
            try databaseWriter.setRating(
                ratingValue,
                for: comic.id,
                in: databaseURL
            )
            applyUpdatedComic(comic.updatingRating(ratingValue))
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Rating",
                message: error.localizedDescription
            )
        }
    }

    func setFavorite(
        _ isFavorite: Bool,
        for comicIDs: [Int64]
    ) -> Bool {
        let visibleComicsByID = Dictionary(uniqueKeysWithValues: (content?.comics ?? []).map { ($0.id, $0) })
        let targetComics = comicIDs.compactMap { visibleComicsByID[$0] }
        guard !targetComics.isEmpty else {
            return false
        }

        AppHaptics.medium()

        do {
            try databaseWriter.setFavorite(
                isFavorite,
                for: targetComics.map(\.id),
                in: databaseURL
            )

            for comic in targetComics {
                applyUpdatedComic(comic.updatingFavorite(isFavorite))
            }
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Favorites",
                message: error.localizedDescription
            )
            return false
        }
    }

    func setReadStatus(
        _ isRead: Bool,
        for comicIDs: [Int64]
    ) -> Bool {
        let visibleComicsByID = Dictionary(uniqueKeysWithValues: (content?.comics ?? []).map { ($0.id, $0) })
        let targetComics = comicIDs.compactMap { visibleComicsByID[$0] }
        guard !targetComics.isEmpty else {
            return false
        }

        AppHaptics.light()

        do {
            try databaseWriter.setReadStatus(
                isRead,
                for: targetComics.map(\.id),
                in: databaseURL
            )

            for comic in targetComics {
                applyUpdatedComic(comic.updatingReadState(isRead))
            }
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Update Read Status",
                message: error.localizedDescription
            )
            return false
        }
    }

    func removeComic(_ comic: LibraryComic) -> Bool {
        do {
            try comicRemovalService.removeComic(comic, from: descriptor)
            AppHaptics.warning()
            loadContent(respectingTransientState: false)
            return true
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Remove Comic",
                message: error.localizedDescription
            )
            return false
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        load()
    }

    func refreshIfLoaded() {
        guard hasLoaded else {
            return
        }

        load()
    }

    func load() {
        loadContent(respectingTransientState: true)
    }

    func setRecentDays(_ days: Int) {
        let normalizedDays = max(1, days)
        guard recentDays != normalizedDays else {
            return
        }

        recentDays = normalizedDays

        guard hasLoaded else {
            return
        }

        refreshSpecialCollectionPreviewsIfNeeded()
    }

    private func loadContent(respectingTransientState: Bool) {
        if respectingTransientState {
            guard !isLoading, !isInitializingLibrary, !isRefreshingLibrary else {
                return
            }
        } else if isLoading {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        databaseSummary = databaseInspector.inspectDatabase(at: databaseURL)

        if let compatibilityIssue = databaseSummary.compatibilityIssueDescription {
            content = nil
            emptyStateMessage = compatibilityIssue
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            clearSearch()
            return
        }

        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }

            var resolvedFolderID = folderID
            do {
                content = try databaseReader.loadFolderContent(
                    databaseURL: databaseURL,
                    folderID: resolvedFolderID
                )
            } catch let error as LibraryDatabaseReadError {
                if case .folderNotFound = error, resolvedFolderID != 1 {
                    resolvedFolderID = 1
                    content = try databaseReader.loadFolderContent(
                        databaseURL: databaseURL,
                        folderID: resolvedFolderID
                    )
                } else {
                    throw error
                }
            }

            folderID = resolvedFolderID
            emptyStateMessage = nil
            refreshSpecialCollectionPreviewsIfNeeded()
            refreshSearchIfNeeded()
        } catch let error as LibraryDatabaseReadError {
            content = nil
            emptyStateMessage = error.localizedDescription
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            clearSearch()
        } catch {
            content = nil
            alert = LibraryAlertState(title: "Failed to Open Library", message: error.localizedDescription)
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            clearSearch()
        }
    }

    func initializeLibrary() {
        guard canInitializeLibrary, !isInitializingLibrary else {
            return
        }

        dismissScanCompletion()
        isInitializingLibrary = true
        emptyStateMessage = nil
        alert = nil
        scanProgress = LibraryScanProgress(
            phase: .preparing,
            currentPath: "/",
            processedFolderCount: 0,
            processedComicCount: 0
        )

        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }
            let sourceURL = accessSession?.sourceURL ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
            let retainedAccessSession = accessSession
            let databaseBootstrapper = self.databaseBootstrapper
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async {
                _ = retainedAccessSession

                let result = Result {
                    try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
                    return try libraryScanner.scanLibrary(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.isInitializingLibrary = false
                    self.scanProgress = nil

                    switch result {
                    case .success(let summary):
                        self.recordMaintenanceStatus(
                            title: "Library Ready",
                            summary: summary,
                            scope: .library,
                            contextPath: nil
                        )
                        self.loadContent(respectingTransientState: false)
                        self.showScanCompletion(
                            title: "Library Ready",
                            summary: summary
                        )
                    case .failure(let error):
                        self.alert = LibraryAlertState(
                            title: "Failed to Initialize Library",
                            message: error.localizedDescription
                        )
                        self.emptyStateMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            isInitializingLibrary = false
            scanProgress = nil
            alert = LibraryAlertState(title: "Failed to Initialize Library", message: error.localizedDescription)
            emptyStateMessage = error.localizedDescription
        }
    }

    func refreshLibrary() {
        guard canRefreshLibrary else {
            return
        }

        dismissScanCompletion()
        isRefreshingLibrary = true
        alert = nil
        scanProgress = LibraryScanProgress(
            phase: .preparing,
            currentPath: "/",
            processedFolderCount: 0,
            processedComicCount: 0
        )

        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }
            let sourceURL = accessSession?.sourceURL ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
            let retainedAccessSession = accessSession
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async {
                _ = retainedAccessSession

                let result = Result {
                    try libraryScanner.rescanLibrary(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.isRefreshingLibrary = false
                    self.scanProgress = nil

                    switch result {
                    case .success(let summary):
                        self.recordMaintenanceStatus(
                            title: "Library Refreshed",
                            summary: summary,
                            scope: .library,
                            contextPath: nil
                        )
                        self.loadContent(respectingTransientState: false)
                        self.showScanCompletion(
                            title: "Library Refreshed",
                            summary: summary
                        )
                    case .failure(let error):
                        self.alert = LibraryAlertState(
                            title: "Failed to Refresh Library",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        } catch {
            isRefreshingLibrary = false
            scanProgress = nil
            alert = LibraryAlertState(title: "Failed to Refresh Library", message: error.localizedDescription)
        }
    }

    func refreshCurrentFolder() {
        guard canRefreshCurrentFolder, let currentFolder = content?.folder else {
            return
        }

        dismissScanCompletion()
        isRefreshingLibrary = true
        alert = nil
        scanProgress = LibraryScanProgress(
            phase: .preparing,
            currentPath: currentFolder.path,
            processedFolderCount: 0,
            processedComicCount: 0
        )

        do {
            if accessSession == nil {
                accessSession = try storageManager.makeAccessSession(for: descriptor)
            }

            let sourceURL = accessSession?.sourceURL ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
            let retainedAccessSession = accessSession
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async {
                _ = retainedAccessSession

                let result = Result {
                    try libraryScanner.refreshFolder(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        folder: currentFolder,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.isRefreshingLibrary = false
                    self.scanProgress = nil

                    switch result {
                    case .success(let summary):
                        self.recordMaintenanceStatus(
                            title: "Folder Refreshed",
                            summary: summary,
                            scope: .folder,
                            contextPath: currentFolder.path
                        )
                        self.loadContent(respectingTransientState: false)
                        self.showScanCompletion(
                            title: "Folder Refreshed",
                            summary: summary
                        )
                    case .failure(let error):
                        self.alert = LibraryAlertState(
                            title: "Failed to Refresh Folder",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        } catch {
            isRefreshingLibrary = false
            scanProgress = nil
            alert = LibraryAlertState(title: "Failed to Refresh Folder", message: error.localizedDescription)
        }
    }

    func importComicFiles(from urls: [URL]) {
        guard canImportComicFiles else {
            if let libraryImportCompatibilityNotice {
                alert = LibraryAlertState(
                    title: "Import Unavailable",
                    message: libraryImportCompatibilityNotice
                )
            }
            return
        }

        var importedCount = 0
        var unsupportedNames: [String] = []
        var failedNames: [String] = []

        do {
            let destinationDirectoryURL = try importDestinationDirectoryURL()
            if !FileManager.default.fileExists(atPath: destinationDirectoryURL.path) {
                try FileManager.default.createDirectory(
                    at: destinationDirectoryURL,
                    withIntermediateDirectories: true
                )
            }

            for url in urls {
                let standardizedURL = url.standardizedFileURL
                let scopedAccess = standardizedURL.startAccessingSecurityScopedResource()
                defer {
                    if scopedAccess {
                        standardizedURL.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                guard values.isDirectory != true, values.isRegularFile == true else {
                    unsupportedNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                let fileExtension = standardizedURL.pathExtension.lowercased()
                guard supportedImportedFileExtensions.contains(fileExtension) else {
                    unsupportedNames.append(standardizedURL.lastPathComponent)
                    continue
                }

                let destinationURL = uniqueDestinationURL(
                    for: standardizedURL,
                    in: destinationDirectoryURL
                )

                do {
                    try FileManager.default.copyItem(at: standardizedURL, to: destinationURL)
                    importedCount += 1
                } catch {
                    failedNames.append(standardizedURL.lastPathComponent)
                }
            }
        } catch {
            alert = LibraryAlertState(
                title: "Failed to Import Comics",
                message: error.localizedDescription
            )
            return
        }

        if importedCount > 0 {
            if canRefreshCurrentFolder {
                refreshCurrentFolder()
            } else if canRefreshLibrary {
                refreshLibrary()
            } else {
                load()
            }
        }

        if importedCount == 0 && unsupportedNames.isEmpty && failedNames.isEmpty {
            return
        }

        var messageLines: [String] = []
        if importedCount > 0 {
            let comicWord = importedCount == 1 ? "comic file" : "comic files"
            messageLines.append("Imported \(importedCount) \(comicWord) into the current library location.")
        }

        if !unsupportedNames.isEmpty {
            let fileWord = unsupportedNames.count == 1 ? "file" : "files"
            messageLines.append("Skipped \(unsupportedNames.count) unsupported \(fileWord).")
        }

        if !failedNames.isEmpty {
            messageLines.append("Failed to import \(failedNames.count) item(s): \(previewList(from: failedNames)).")
        }

        alert = LibraryAlertState(
            title: importedCount > 0 ? "Import Completed" : "Import Finished with Warnings",
            message: messageLines.joined(separator: "\n")
        )
    }

    func importLibraryComicInfo(policy: ComicInfoImportPolicy) {
        guard canImportLibraryComicInfo else {
            return
        }

        performComicInfoImport(
            policy: policy,
            initialPath: "/",
            emptyTitle: "No Comics Found",
            emptyMessage: "The library does not contain any comics yet."
        ) { databaseURL, databaseReader in
            try databaseReader.loadAllComics(databaseURL: databaseURL)
        }
    }

    func importCurrentFolderComicInfo(policy: ComicInfoImportPolicy) {
        guard canImportCurrentFolderComicInfo, let currentFolder = content?.folder else {
            return
        }

        performComicInfoImport(
            policy: policy,
            initialPath: currentFolder.path,
            emptyTitle: "No Comics Found",
            emptyMessage: "The current folder does not contain any comics yet."
        ) { databaseURL, databaseReader in
            try databaseReader.loadComicsRecursively(
                databaseURL: databaseURL,
                folderID: currentFolder.id
            )
        }
    }

    func coverURL(for folder: LibraryFolder) -> URL? {
        coverLocator.coverURL(for: folder, metadataRootURL: metadataRootURL)
    }

    func coverURL(for comic: LibraryComic) -> URL? {
        coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL)
    }

    func coverSource(for comic: LibraryComic) -> LocalComicCoverSource? {
        let sourceRootURL = accessSession?.sourceURL
            ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
        return LocalComicCoverSource(
            fileURL: resolveComicFileURL(for: comic, sourceRootURL: sourceRootURL),
            cacheURL: coverLocator.plannedCoverURL(for: comic, metadataRootURL: metadataRootURL)
        )
    }

    func heroSourceID(for comic: LibraryComic) -> String {
        "library-comic-\(descriptor.id.uuidString)-\(comic.id)"
    }

    func cachedTransitionImage(for comic: LibraryComic) -> UIImage? {
        LocalCoverTransitionCache.shared.image(for: heroSourceID(for: comic))
    }

    func dismissScanCompletion() {
        scanCompletionDismissTask?.cancel()
        scanCompletionDismissTask = nil
        scanCompletion = nil
    }

    private var databaseExists: Bool {
        FileManager.default.fileExists(atPath: databaseURL.path)
    }

    private func importDestinationDirectoryURL() throws -> URL {
        if accessSession == nil {
            accessSession = try storageManager.makeAccessSession(for: descriptor)
        }

        let sourceRootURL = accessSession?.sourceURL ?? URL(fileURLWithPath: descriptor.sourcePath, isDirectory: true)
        guard let content else {
            return sourceRootURL
        }

        guard !content.folder.isRoot else {
            return sourceRootURL
        }

        let relativePath = content.folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            return sourceRootURL
        }

        return sourceRootURL.appendingPathComponent(relativePath, isDirectory: true)
    }

    private func resolveComicFileURL(
        for comic: LibraryComic,
        sourceRootURL: URL
    ) -> URL {
        let relativePath = {
            let rawPath = comic.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawPath.isEmpty {
                return comic.fileName
            }

            return rawPath
        }()

        if relativePath.hasPrefix("/") {
            return sourceRootURL.appendingPathComponent(String(relativePath.dropFirst()))
        }

        return sourceRootURL.appendingPathComponent(relativePath)
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directoryURL: URL) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: preferredURL.path) else {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let fileExtension = sourceURL.pathExtension
            var counter = 1

            while true {
                let candidateName: String
                if fileExtension.isEmpty {
                    candidateName = "\(baseName) (\(counter))"
                } else {
                    candidateName = "\(baseName) (\(counter)).\(fileExtension)"
                }

                let candidateURL = directoryURL.appendingPathComponent(candidateName)
                if !FileManager.default.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
                counter += 1
            }
        }

        return preferredURL
    }

    private func previewList(from names: [String], limit: Int = 3) -> String {
        let uniqueSortedNames = Array(Set(names)).sorted()
        guard uniqueSortedNames.count > limit else {
            return uniqueSortedNames.joined(separator: ", ")
        }

        let preview = uniqueSortedNames.prefix(limit).joined(separator: ", ")
        return "\(preview), +\(uniqueSortedNames.count - limit) more"
    }

    private func configureSearch() {
        $searchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.searchLibrary(matching: query)
            }
            .store(in: &cancellables)
    }

    private func showScanCompletion(title: String, summary: LibraryScanSummary) {
        showCompletion(
            title: title,
            message: summary.completionLine
        )
    }

    private func recordMaintenanceStatus(
        title: String,
        summary: LibraryScanSummary,
        scope: LibraryMaintenanceRecord.Scope,
        contextPath: String?
    ) {
        lastInitializationSummary = summary
        let record = LibraryMaintenanceRecord(
            libraryID: descriptor.id,
            title: title,
            summary: summary,
            scope: scope,
            contextPath: contextPath,
            scannedAt: Date()
        )
        maintenanceRecord = record
        maintenanceStatusStore.saveRecord(record)
    }

    private func showCompletion(title: String, message: String) {
        let completion = LibraryScanCompletionState(
            title: title,
            message: message
        )

        scanCompletionDismissTask?.cancel()
        scanCompletion = completion

        scanCompletionDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.scanCompletion?.id == completion.id else {
                    return
                }

                self?.scanCompletion = nil
                self?.scanCompletionDismissTask = nil
            }
        }
    }

    private func performComicInfoImport(
        policy: ComicInfoImportPolicy,
        initialPath: String?,
        emptyTitle: String,
        emptyMessage: String,
        comicsLoader: @escaping (URL, LibraryDatabaseReader) throws -> [LibraryComic]
    ) {
        guard !isInitializingLibrary, !isRefreshingLibrary else {
            return
        }

        dismissScanCompletion()
        isRefreshingLibrary = true
        alert = nil
        scanProgress = LibraryScanProgress(
            phase: .preparing,
            currentPath: initialPath,
            processedFolderCount: 0,
            processedComicCount: 0
        )

        let descriptor = self.descriptor
        let databaseReader = self.databaseReader
        let databaseURL = self.databaseURL
        let comicInfoImportService = self.comicInfoImportService
        let progressHandler = makeScanProgressHandler()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                let comics = try comicsLoader(databaseURL, databaseReader)
                guard !comics.isEmpty else {
                    return ComicInfoImportBatchResult(
                        totalCount: 0,
                        importedCount: 0,
                        skippedCount: 0,
                        failedTitles: []
                    )
                }

                return try comicInfoImportService.importEmbeddedComicInfoSynchronously(
                    for: descriptor,
                    comics: comics,
                    policy: policy,
                    progressHandler: progressHandler
                )
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.isRefreshingLibrary = false
                self.scanProgress = nil

                switch result {
                case .success(let summary):
                    guard summary.totalCount > 0 else {
                        self.alert = LibraryAlertState(
                            title: emptyTitle,
                            message: emptyMessage
                        )
                        return
                    }

                    self.loadContent(respectingTransientState: false)
                    self.showCompletion(
                        title: summary.alertTitle,
                        message: summary.alertMessage
                    )
                case .failure(let error):
                    self.alert = LibraryAlertState(
                        title: "Failed to Import ComicInfo",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func searchLibrary(matching query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }

        let searchToken = UUID()
        activeSearchToken = searchToken
        isSearching = true

        let databaseReader = self.databaseReader
        let databaseURL = self.databaseURL

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try databaseReader.searchLibrary(
                    databaseURL: databaseURL,
                    query: trimmedQuery,
                    limit: Self.searchResultLimit
                )
            }

            Task { @MainActor [weak self] in
                guard let self, self.activeSearchToken == searchToken else {
                    return
                }

                self.isSearching = false

                switch result {
                case .success(let results):
                    self.searchResults = results
                case .failure(let error):
                    self.searchResults = nil
                    self.alert = LibraryAlertState(title: "Search Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func refreshSearchIfNeeded() {
        guard hasActiveSearch else {
            return
        }

        searchLibrary(matching: searchQuery)
    }

    private func refreshSpecialCollectionPreviewsIfNeeded() {
        guard folderID == 1 else {
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            return
        }

        continueReadingComics = (try? databaseReader.loadSpecialListComics(
            databaseURL: databaseURL,
            kind: .reading,
            recentDays: recentDays
        )) ?? []

        recentComics = (try? databaseReader.loadSpecialListComics(
            databaseURL: databaseURL,
            kind: .recent,
            recentDays: recentDays
        )) ?? []

        favoritesComics = (try? databaseReader.loadSpecialListComics(
            databaseURL: databaseURL,
            kind: .favorites,
            recentDays: recentDays
        )) ?? []

        if let counts = try? databaseReader.loadSpecialListCounts(
            databaseURL: databaseURL,
            recentDays: recentDays
        ) {
            specialCollectionCounts = counts
        } else {
            specialCollectionCounts = [
                .reading: continueReadingComics.count,
                .favorites: favoritesComics.count,
                .recent: recentComics.count
            ]
        }
    }

    private func existingComicSnapshot(for comicID: Int64) -> LibraryComic? {
        if let comic = content?.comics.first(where: { $0.id == comicID }) {
            return comic
        }

        if let comic = continueReadingComics.first(where: { $0.id == comicID }) {
            return comic
        }

        if let comic = recentComics.first(where: { $0.id == comicID }) {
            return comic
        }

        if let comic = favoritesComics.first(where: { $0.id == comicID }) {
            return comic
        }

        if let comic = searchResults?.comics.first(where: { $0.id == comicID }) {
            return comic
        }

        return nil
    }

    private func refreshSpecialCollectionCountsLocally(
        previous: LibraryComic?,
        updated: LibraryComic
    ) {
        var counts = specialCollectionCounts
        guard !counts.isEmpty else {
            return
        }

        let now = Date()

        if let previous {
            let wasReading = previous.belongs(to: .reading, now: now)
            let isReading = updated.belongs(to: .reading, now: now)
            if wasReading != isReading {
                counts[.reading] = max(0, (counts[.reading] ?? continueReadingComics.count) + (isReading ? 1 : -1))
            }

            let wasFavorite = previous.belongs(to: .favorites, now: now)
            let isFavorite = updated.belongs(to: .favorites, now: now)
            if wasFavorite != isFavorite {
                counts[.favorites] = max(0, (counts[.favorites] ?? favoritesComics.count) + (isFavorite ? 1 : -1))
            }

            let wasRecent = previous.belongs(
                to: .recent,
                recentDays: recentDays,
                now: now
            )
            let isRecent = updated.belongs(
                to: .recent,
                recentDays: recentDays,
                now: now
            )
            if wasRecent != isRecent {
                counts[.recent] = max(0, (counts[.recent] ?? recentComics.count) + (isRecent ? 1 : -1))
            }
        } else {
            counts[.reading] = continueReadingComics.count
            counts[.favorites] = max(counts[.favorites] ?? 0, favoritesComics.count)
            counts[.recent] = recentComics.count
        }

        specialCollectionCounts = counts
    }

    private func clearSearch() {
        activeSearchToken = UUID()
        isSearching = false
        searchResults = nil
    }

    private func makeScanProgressHandler() -> (LibraryScanProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.scanProgress = progress
            }
        }
    }
}
