import Combine
import Foundation
import os
import UIKit

@MainActor
final class LibraryBrowserViewModel: ObservableObject, LoadableViewModel {
    private static let liveImportReloadDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(700)

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
    @Published private(set) var importProgress: ImportedComicsImportProgress?
    @Published private(set) var isImportingComics = false
    @Published var searchQuery = ""
    @Published var alert: AppAlertState?

    let descriptor: LibraryDescriptor
    private(set) var folderID: Int64

    private let storageManager: LibraryStorageManager
    private let databaseReader: LibraryDatabaseReader
    private let databaseWriter: LibraryDatabaseWriter
    private let databaseBootstrapper: LibraryDatabaseBootstrapper
    private let libraryScanner: any LibraryScanning
    private let maintenanceStatusStore: LibraryMaintenanceStatusStore
    private let coverLocator: LibraryCoverLocator
    private let comicInfoImportService: ComicInfoImportService
    private let importedComicsImportService: ImportedComicsImportService
    private let comicRemovalService: LibraryComicRemovalService
    private let remoteBackgroundImportController: RemoteBackgroundImportController
    private let databaseInspector: SQLiteDatabaseInspector
    private let logger = AppLog.library

    private let metadataRootURL: URL
    private let databaseURL: URL
    private var activeSearchToken = UUID()
    private var accessSession: LibraryAccessSession?
    private var cancellables = Set<AnyCancellable>()
    private var scanCompletionDismissTask: Task<Void, Never>?
    private var comicImportTask: Task<Void, Never>?
    private var comicImportCancellationController: LibraryImportCancellationController?
    private var activeComicImportID: UUID?
    private var hasLoaded = false
    private var hasAttemptedAutomaticImportRecovery = false
    private var hasLoggedSourceRootResolutionFailure = false
    private let previewCollectionLimit = 6
    nonisolated private static let searchResultLimit = 40
    nonisolated private static let liveImportNotificationLibraryIDKey = "libraryID"
    private var recentDays = LibraryRecentWindowOption.defaultOption.dayCount

    init(
        descriptor: LibraryDescriptor,
        folderID: Int64 = 1,
        storageManager: LibraryStorageManager,
        databaseReader: LibraryDatabaseReader,
        databaseWriter: LibraryDatabaseWriter,
        databaseBootstrapper: LibraryDatabaseBootstrapper,
        libraryScanner: any LibraryScanning,
        maintenanceStatusStore: LibraryMaintenanceStatusStore,
        coverLocator: LibraryCoverLocator,
        comicInfoImportService: ComicInfoImportService,
        importedComicsImportService: ImportedComicsImportService,
        comicRemovalService: LibraryComicRemovalService,
        remoteBackgroundImportController: RemoteBackgroundImportController,
        databaseInspector: SQLiteDatabaseInspector? = nil
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
        self.remoteBackgroundImportController = remoteBackgroundImportController
        self.databaseInspector = databaseInspector ?? SQLiteDatabaseInspector()
        self.metadataRootURL = storageManager.metadataRootURL(for: descriptor)
        self.databaseURL = storageManager.databaseURL(for: descriptor)
        let initialMaintenanceRecord = maintenanceStatusStore.loadRecord(for: descriptor.id)
        self.maintenanceRecord = initialMaintenanceRecord
        self.lastInitializationSummary = initialMaintenanceRecord?.summary
        self.databaseSummary = self.databaseInspector.inspectDatabase(at: self.databaseURL)
        configureSearch()
        configureLiveImportUpdates()
    }

    @Published private(set) var databaseSummary: LibraryDatabaseSummary

    var navigationTitle: String {
        if let content {
            return content.folder.isRoot ? descriptor.displayName : content.folder.displayName
        }

        return descriptor.displayName
    }

    var folderPath: String {
        content?.folder.path ?? descriptor.sourcePath
    }

    var databasePath: String {
        databaseURL.path
    }

    var canInitializeLibrary: Bool {
        content == nil && !databaseSummary.exists && folderID == 1
    }

    var canRefreshLibrary: Bool {
        folderID == 1
            && databaseSummary.exists
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canRefreshCurrentFolder: Bool {
        folderID != 1
            && content != nil
            && databaseSummary.exists
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canScanFromCurrentContext: Bool {
        canRefreshLibrary || canRefreshCurrentFolder
    }

    var canImportLibraryComicInfo: Bool {
        folderID == 1
            && databaseSummary.exists
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canImportCurrentFolderComicInfo: Bool {
        folderID != 1
            && content != nil
            && databaseSummary.exists
            && !isInitializingLibrary
            && !isRefreshingLibrary
    }

    var canImportComicFiles: Bool {
        content != nil
            && databaseSummary.exists
            && supportsDirectLibraryImports
            && !isInitializingLibrary
            && !isRefreshingLibrary
            && !isImportingComics
    }

    var libraryImportNotice: String? {
        switch importedComicsImportService.importAvailability(for: descriptor) {
        case .available:
            return nil
        case .unavailable(let message):
            return message
        }
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

        if folderID == 1 {
            continueReadingComics = updatedContinueReadingComics(afterApplying: updatedComic)
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

    private func updatedContinueReadingComics(afterApplying updatedComic: LibraryComic) -> [LibraryComic] {
        var comics = continueReadingComics.filter { $0.id != updatedComic.id }

        if updatedComic.isContinueReadingCandidate {
            comics.append(updatedComic)
        }

        return comics.sorted { lhs, rhs in
            let lhsDate = lhs.lastOpenedAt ?? lhs.addedAt ?? .distantPast
            let rhsDate = rhs.lastOpenedAt ?? rhs.addedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
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
            alert = AppAlertState(
                title: String(localized: "Failed to Update Favorites"),
                message: error.userFacingMessage
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
            alert = AppAlertState(
                title: String(localized: "Failed to Update Read Status"),
                message: error.userFacingMessage
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
            alert = AppAlertState(
                title: String(localized: "Failed to Update Rating"),
                message: error.userFacingMessage
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
            alert = AppAlertState(
                title: String(localized: "Failed to Update Favorites"),
                message: error.userFacingMessage
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
            alert = AppAlertState(
                title: String(localized: "Failed to Update Read Status"),
                message: error.userFacingMessage
            )
            return false
        }
    }

    func removeComic(_ comic: LibraryComic) -> Bool {
        guard beginExclusiveLibraryStorageOperation() else {
            return false
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        do {
            try comicRemovalService.removeComic(comic, from: descriptor)
            AppHaptics.warning()
            loadContent(respectingTransientState: false)
            return true
        } catch {
            alert = AppAlertState(
                title: String(localized: "Failed to Remove Comic"),
                message: error.userFacingMessage
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

        if shouldAttemptAutomaticImportRecovery() {
            hasAttemptedAutomaticImportRecovery = true
            initializeLibrary()
            return
        }

        if databaseSummary.exists {
            hasAttemptedAutomaticImportRecovery = false
        }

        if let issue = databaseSummary.issueDescription {
            content = nil
            emptyStateMessage = issue
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
            hasAttemptedAutomaticImportRecovery = false
            refreshSpecialCollectionPreviewsIfNeeded()
            refreshSearchIfNeeded()
        } catch let error as LibraryDatabaseReadError {
            content = nil
            emptyStateMessage = error.userFacingMessage
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            clearSearch()
        } catch {
            content = nil
            alert = AppAlertState(
                title: String(localized: "Failed to Open Library"),
                message: error.userFacingMessage
            )
            continueReadingComics = []
            recentComics = []
            favoritesComics = []
            specialCollectionCounts = [:]
            clearSearch()
        }
    }

    private func shouldAttemptAutomaticImportRecovery() -> Bool {
        guard !databaseSummary.exists,
              folderID == 1,
              !hasAttemptedAutomaticImportRecovery,
              let maintenanceRecord,
              maintenanceRecord.scope == .importIndex
        else {
            return false
        }

        return Date().timeIntervalSince(maintenanceRecord.scannedAt) <= 600
    }

    func initializeLibrary() {
        guard canInitializeLibrary, !isInitializingLibrary else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }
        let storageMaintenanceController = remoteBackgroundImportController

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
            let sourceURL = try resolvedSourceRootURL()
            let retainedAccessSession = accessSession
            let databaseBootstrapper = self.databaseBootstrapper
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = retainedAccessSession

                let result = Result {
                    try databaseBootstrapper.createDatabaseIfNeeded(at: databaseURL)
                    return try libraryScanner.scanLibrary(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        cancellationCheck: nil,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    defer {
                        storageMaintenanceController.endExclusiveStorageMaintenance()
                    }
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
                            title: String(localized: "Library Ready"),
                            summary: summary
                        )
                    case .failure(let error):
                        let sourcePath = AppLogSanitizer.path(sourceURL.path)
                        let databasePath = AppLogSanitizer.path(databaseURL.path)
                        let errorDescription = AppLogSanitizer.errorDescription(error)
                        self.logger.error(
                            "Failed to initialize library \(self.descriptor.id.uuidString, privacy: .public) from \(sourcePath, privacy: .public). Database: \(databasePath, privacy: .public). Error: \(errorDescription, privacy: .public)"
                        )
                        self.alert = AppAlertState(
                            title: String(localized: "Failed to Initialize Library"),
                            message: error.userFacingMessage
                        )
                        self.emptyStateMessage = error.userFacingMessage
                    }
                }
            }
        } catch {
            storageMaintenanceController.endExclusiveStorageMaintenance()
            isInitializingLibrary = false
            scanProgress = nil
            alert = AppAlertState(
                title: String(localized: "Failed to Initialize Library"),
                message: error.userFacingMessage
            )
            emptyStateMessage = error.userFacingMessage
        }
    }

    func refreshLibrary() {
        guard canRefreshLibrary else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }
        let storageMaintenanceController = remoteBackgroundImportController

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
            let sourceURL = try resolvedSourceRootURL()
            let retainedAccessSession = accessSession
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = retainedAccessSession

                let result = Result {
                    try libraryScanner.rescanLibrary(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        cancellationCheck: nil,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    defer {
                        storageMaintenanceController.endExclusiveStorageMaintenance()
                    }
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
                            title: String(localized: "Library Refreshed"),
                            summary: summary
                        )
                    case .failure(let error):
                        let sourcePath = AppLogSanitizer.path(sourceURL.path)
                        let databasePath = AppLogSanitizer.path(databaseURL.path)
                        let errorDescription = AppLogSanitizer.errorDescription(error)
                        self.logger.error(
                            "Failed to refresh library \(self.descriptor.id.uuidString, privacy: .public) from \(sourcePath, privacy: .public). Database: \(databasePath, privacy: .public). Error: \(errorDescription, privacy: .public)"
                        )
                        self.alert = AppAlertState(
                            title: String(localized: "Failed to Refresh Library"),
                            message: error.userFacingMessage
                        )
                    }
                }
            }
        } catch {
            storageMaintenanceController.endExclusiveStorageMaintenance()
            isRefreshingLibrary = false
            scanProgress = nil
            alert = AppAlertState(
                title: String(localized: "Failed to Refresh Library"),
                message: error.userFacingMessage
            )
        }
    }

    func refreshCurrentFolder() {
        guard canRefreshCurrentFolder, let currentFolder = content?.folder else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }
        let storageMaintenanceController = remoteBackgroundImportController

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
            let sourceURL = try resolvedSourceRootURL()
            let retainedAccessSession = accessSession
            let libraryScanner = self.libraryScanner
            let databaseURL = self.databaseURL
            let progressHandler = makeScanProgressHandler()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = retainedAccessSession

                let result = Result {
                    try libraryScanner.refreshFolder(
                        sourceRootURL: sourceURL,
                        databaseURL: databaseURL,
                        folder: currentFolder,
                        cancellationCheck: nil,
                        progressHandler: progressHandler
                    )
                }

                Task { @MainActor [weak self] in
                    defer {
                        storageMaintenanceController.endExclusiveStorageMaintenance()
                    }
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
                            title: String(localized: "Folder Refreshed"),
                            summary: summary
                        )
                    case .failure(let error):
                        self.alert = AppAlertState(
                            title: String(localized: "Failed to Refresh Folder"),
                            message: error.userFacingMessage
                        )
                    }
                }
            }
        } catch {
            storageMaintenanceController.endExclusiveStorageMaintenance()
            isRefreshingLibrary = false
            scanProgress = nil
            alert = AppAlertState(
                title: String(localized: "Failed to Refresh Folder"),
                message: error.userFacingMessage
            )
        }
    }

    func importComicFiles(from urls: [URL]) {
        guard canImportComicFiles else {
            if let libraryImportNotice {
                alert = AppAlertState(
                    title: String(localized: "Import Unavailable"),
                    message: libraryImportNotice
                )
            }
            return
        }

        guard !urls.isEmpty, !isImportingComics else {
            return
        }
        guard beginExclusiveLibraryStorageOperation() else {
            return
        }

        let cancellationController = LibraryImportCancellationController()
        let importID = UUID()
        comicImportCancellationController = cancellationController
        activeComicImportID = importID
        isImportingComics = true
        importProgress = nil
        alert = nil
        let destinationRelativePath = importDestinationRelativePath()

        comicImportTask = Task {
            await performComicFileImport(
                from: urls,
                destinationRelativePath: destinationRelativePath,
                cancellationController: cancellationController,
                importID: importID
            )
        }
    }

    func cancelComicImport() {
        comicImportCancellationController?.cancel()
        comicImportTask?.cancel()
    }

    private func performComicFileImport(
        from urls: [URL],
        destinationRelativePath: String?,
        cancellationController: LibraryImportCancellationController,
        importID: UUID
    ) async {
        defer {
            isImportingComics = false
            importProgress = nil
            comicImportCancellationController = nil
            comicImportTask = nil
            activeComicImportID = nil
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        do {
            let result = try await importedComicsImportService.importComicResourcesAsync(
                from: urls,
                traverseDirectories: false,
                accessSecurityScopedResources: true,
                destinationSelection: .library(descriptor.id),
                destinationRelativePath: destinationRelativePath,
                progressHandler: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard self?.activeComicImportID == importID else {
                            return
                        }
                        self?.importProgress = progress
                    }
                },
                cancellationCheck: cancellationController.checkCancelled
            )

            loadContent(respectingTransientState: false)
            guard result.hasImportedAnyComics
                    || !result.unsupportedItemNames.isEmpty
                    || !result.failedItemNames.isEmpty
            else {
                return
            }

            var messageLines: [String] = []
            if result.importedComicCount > 0 {
                if result.importedComicCount == 1 {
                    messageLines.append(String(localized: "Imported 1 comic file into the current library location."))
                } else {
                    messageLines.append(
                        String(localized: "Imported \(result.importedComicCount) comic files into the current library location.")
                    )
                }
            }
            if let scanSummary = result.scanSummary {
                messageLines.append(scanSummary.indexedSummaryLine + ".")
            } else if let scanErrorMessage = result.scanErrorMessage {
                messageLines.append(String(localized: "Automatic indexing failed: \(scanErrorMessage)"))
            }
            if !result.unsupportedItemNames.isEmpty {
                if result.unsupportedItemNames.count == 1 {
                    messageLines.append(String(localized: "Skipped 1 unsupported item."))
                } else {
                    messageLines.append(
                        String(localized: "Skipped \(result.unsupportedItemNames.count) unsupported items.")
                    )
                }
            }
            if !result.failedItemNames.isEmpty {
                let failedItemsPreview = NamePreviewFormatter.preview(from: result.failedItemNames)
                if result.failedItemNames.count == 1 {
                    messageLines.append(String(localized: "Failed to import 1 item: \(failedItemsPreview)."))
                } else {
                    messageLines.append(
                        String(localized: "Failed to import \(result.failedItemNames.count) items: \(failedItemsPreview).")
                    )
                }
            }

            alert = AppAlertState(
                title: result.hasImportedAnyComics
                    ? String(localized: "Import Completed")
                    : String(localized: "Import Finished with Warnings"),
                message: messageLines.joined(separator: "\n")
            )
        } catch is CancellationError {
            logger.notice(
                "Library browser comic import canceled libraryID=\(self.descriptor.id.uuidString, privacy: .public)"
            )
        } catch {
            logger.error(
                "Library browser comic import failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            alert = AppAlertState(
                title: String(localized: "Failed to Import Comics"),
                message: error.userFacingMessage
            )
        }
    }

    func importLibraryComicInfo(policy: ComicInfoImportPolicy) {
        guard canImportLibraryComicInfo else {
            return
        }

        performComicInfoImport(
            policy: policy,
            initialPath: "/",
            emptyTitle: String(localized: "No Comics Found"),
            emptyMessage: String(localized: "The library does not contain any comics yet.")
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
            emptyTitle: String(localized: "No Comics Found"),
            emptyMessage: String(localized: "The current folder does not contain any comics yet.")
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

    func previewCoverURLs(for folder: LibraryFolder) -> [URL] {
        coverLocator.previewCoverURLs(for: folder, metadataRootURL: metadataRootURL)
    }

    func coverURL(for comic: LibraryComic) -> URL? {
        coverLocator.coverURL(for: comic, metadataRootURL: metadataRootURL)
    }

    func coverSource(for comic: LibraryComic) -> LocalComicCoverSource? {
        guard let sourceRootURL = resolvedSourceRootURLIfAvailable() else {
            return nil
        }

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

    private func importDestinationRelativePath() -> String? {
        guard let content else {
            return nil
        }

        guard !content.folder.isRoot else {
            return nil
        }

        let relativePath = content.folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.isEmpty ? nil : relativePath
    }

    private func beginExclusiveLibraryStorageOperation() -> Bool {
        guard remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            alert = AppAlertState(
                title: String(localized: "Library Busy"),
                message: String(localized: "Finish the current import or storage task, then try again.")
            )
            return false
        }

        return true
    }

    private func resolvedSourceRootURL() throws -> URL {
        if accessSession == nil {
            accessSession = try storageManager.makeAccessSession(for: descriptor)
        }

        if let sourceURL = accessSession?.sourceURL {
            return sourceURL
        }

        return try storageManager.restoreSourceURL(for: descriptor)
    }

    private func resolvedSourceRootURLIfAvailable() -> URL? {
        do {
            return try resolvedSourceRootURL()
        } catch {
            logSourceRootResolutionFailureOnce(error: error)
            return nil
        }
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

    private func logSourceRootResolutionFailureOnce(error: Error) {
        guard !hasLoggedSourceRootResolutionFailure else {
            return
        }

        hasLoggedSourceRootResolutionFailure = true
        logger.warning(
            "Library browser source root resolution failed libraryID=\(self.descriptor.id.uuidString, privacy: .public) kind=\(self.descriptor.kind.rawValue, privacy: .public) root=\(AppLogSanitizer.path(self.descriptor.rootPath), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
        )
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

    private func configureLiveImportUpdates() {
        NotificationCenter.default.publisher(for: .libraryContentsDidChange)
            .compactMap { notification in
                notification.userInfo?[Self.liveImportNotificationLibraryIDKey] as? UUID
            }
            .filter { [descriptor] libraryID in
                libraryID == descriptor.id
            }
            .debounce(for: Self.liveImportReloadDebounce, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                guard !self.isInitializingLibrary,
                      !self.isRefreshingLibrary,
                      !self.isImportingComics else {
                    return
                }

                self.loadContent(respectingTransientState: false)
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
                        self.alert = AppAlertState(
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
                    self.alert = AppAlertState(
                        title: String(localized: "Failed to Import ComicInfo"),
                        message: error.userFacingMessage
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
                    self.alert = AppAlertState(
                        title: String(localized: "Search Failed"),
                        message: error.userFacingMessage
                    )
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

        continueReadingComics = loadSpecialCollectionPreview(kind: .reading)
        recentComics = loadSpecialCollectionPreview(kind: .recent)
        favoritesComics = loadSpecialCollectionPreview(kind: .favorites)
        specialCollectionCounts = loadSpecialCollectionCounts()
    }

    private func loadSpecialCollectionPreview(kind: LibrarySpecialCollectionKind) -> [LibraryComic] {
        do {
            return try databaseReader.loadSpecialListComics(
                databaseURL: databaseURL,
                kind: kind,
                recentDays: recentDays
            )
        } catch {
            logger.warning(
                "Library special preview fallback libraryID=\(self.descriptor.id.uuidString, privacy: .public) kind=\(kind.rawValue, privacy: .public) result=empty error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return []
        }
    }

    private func loadSpecialCollectionCounts() -> [LibrarySpecialCollectionKind: Int] {
        let fallbackCounts: [LibrarySpecialCollectionKind: Int] = [
            .reading: continueReadingComics.count,
            .favorites: favoritesComics.count,
            .recent: recentComics.count
        ]

        do {
            return try databaseReader.loadSpecialListCounts(
                databaseURL: databaseURL,
                recentDays: recentDays
            )
        } catch {
            logger.warning(
                "Library special counts fallback libraryID=\(self.descriptor.id.uuidString, privacy: .public) result=previewCounts error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            return fallbackCounts
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
