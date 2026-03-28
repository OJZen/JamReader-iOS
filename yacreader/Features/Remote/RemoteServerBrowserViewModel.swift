import Combine
import Foundation

struct RemoteBrowserLoadIssue: Hashable {
    enum Kind: Hashable {
        case authentication
        case connection
        case shareUnavailable
        case remotePathUnavailable
        case accessDenied
        case generic
    }

    let kind: Kind
    let title: String
    let message: String
    let recoverySuggestion: String

    var showsManageServersAction: Bool {
        switch kind {
        case .authentication, .shareUnavailable, .accessDenied:
            return true
        case .connection, .remotePathUnavailable, .generic:
            return false
        }
    }

    var prefersPathRecoveryActions: Bool {
        switch kind {
        case .remotePathUnavailable, .accessDenied:
            return true
        case .authentication, .connection, .shareUnavailable, .generic:
            return false
        }
    }

    var allowsOfflineRecovery: Bool {
        switch kind {
        case .connection, .shareUnavailable, .authentication, .generic:
            return true
        case .remotePathUnavailable, .accessDenied:
            return false
        }
    }
}

@MainActor
final class RemoteServerBrowserViewModel: ObservableObject {
    private static let lastBrowsedPathKeyPrefix = "remoteServerBrowser.lastPath."

    @Published private(set) var items: [RemoteDirectoryItem] = []
    @Published private(set) var progressByItemID: [String: RemoteComicReadingSession] = [:]
    @Published private(set) var cacheAvailabilityByItemID: [String: RemoteComicCachedAvailability] = [:]
    @Published private(set) var recentSessions: [RemoteComicReadingSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadIssue: RemoteBrowserLoadIssue?
    @Published private(set) var activeImportDescription: String?
    @Published private(set) var isCurrentFolderSaved = false
    @Published var feedback: RemoteBrowserFeedbackState?
    @Published var alert: RemoteAlertState?

    let profile: RemoteServerProfile
    let currentPath: String
    let capabilities: RemoteServerBrowserCapabilities

    private let browsingService: RemoteServerBrowsingService
    private let readingProgressStore: RemoteReadingProgressStore
    private let importedComicsImportService: ImportedComicsImportService
    private let folderShortcutStore: RemoteFolderShortcutStore
    private var hasLoaded = false
    private var progressRefreshTask: Task<Void, Never>?

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        browsingService: RemoteServerBrowsingService,
        readingProgressStore: RemoteReadingProgressStore,
        importedComicsImportService: ImportedComicsImportService,
        folderShortcutStore: RemoteFolderShortcutStore
    ) {
        self.profile = profile
        self.currentPath = Self.initialPath(for: profile, explicitPath: currentPath)
        self.capabilities = browsingService.capabilities(for: profile.providerKind)
        self.browsingService = browsingService
        self.readingProgressStore = readingProgressStore
        self.importedComicsImportService = importedComicsImportService
        self.folderShortcutStore = folderShortcutStore
        self.isCurrentFolderSaved = folderShortcutStore.containsShortcut(
            for: profile.id,
            providerKind: profile.providerKind,
            providerRootIdentifier: profile.normalizedProviderRootIdentifier,
            path: Self.normalizedShortcutPath(currentPath ?? Self.initialPath(for: profile, explicitPath: currentPath))
        )
    }

    var navigationTitle: String {
        if currentPath.isEmpty || currentPath == "/" {
            return profile.name
        }

        return currentPath.split(separator: "/").last.map(String.init) ?? profile.name
    }

    var rootPath: String {
        profile.normalizedBaseDirectoryPath
    }

    var isAtRootPath: Bool {
        currentPath == rootPath
    }

    var parentPath: String? {
        let rootComponents = Self.pathComponents(for: rootPath)
        let currentComponents = Self.pathComponents(for: currentPath)
        guard currentComponents.count > rootComponents.count else {
            return nil
        }

        let parentComponents = Array(currentComponents.dropLast())
        if parentComponents.isEmpty {
            return ""
        }

        return "/" + parentComponents.joined(separator: "/")
    }

    var currentPathDisplayText: String {
        currentPath.isEmpty ? "/" : currentPath
    }

    var directories: [RemoteDirectoryItem] {
        items.filter(\.isDirectory)
    }

    var comicFiles: [RemoteDirectoryItem] {
        items.filter(\.canOpenAsComic)
    }

    var canImportCurrentFolderRecursively: Bool {
        !comicFiles.isEmpty || !directories.isEmpty
    }

    var unsupportedFileCount: Int {
        items.reduce(into: 0) { count, item in
            if item.kind == .unsupportedFile {
                count += 1
            }
        }
    }

    var connectionDetailText: String {
        profile.connectionDisplayPath
    }

    var currentFolderShortcutTitle: String {
        if currentPath == rootPath || currentPath.isEmpty {
            return "\(profile.name) Root"
        }

        return navigationTitle
    }

    var loadErrorMessage: String? {
        loadIssue?.message
    }

    var offlineRecoverySessions: [RemoteComicReadingSession] {
        recentSessions.filter { browsingService.cachedAvailability(for: $0.comicFileReference).hasLocalCopy }
    }

    var recoverySession: RemoteComicReadingSession? {
        offlineRecoverySessions.first
    }

    var offlineRecoveryCount: Int {
        offlineRecoverySessions.count
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let loadedItems = try await browsingService.listDirectory(
                for: profile,
                path: currentPath
            )
            items = loadedItems.sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind == .directory
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            progressByItemID = [:]
            cacheAvailabilityByItemID = [:]
            recentSessions = []
            loadIssue = nil
            Self.rememberLastBrowsedPath(currentPath, for: profile)
            refreshShortcutState()
            scheduleProgressStateRefresh()
        } catch {
            progressRefreshTask?.cancel()
            progressRefreshTask = nil
            items = []
            progressByItemID = [:]
            cacheAvailabilityByItemID = [:]
            recentSessions = recentSessionsForProfile()
            loadIssue = makeLoadIssue(from: error)
            refreshShortcutState()
        }
    }

    func refreshProgressState() {
        let sessionsByPath = ((try? readingProgressStore.loadSessions()) ?? [])
            .reduce(into: [String: RemoteComicReadingSession]()) { result, session in
                guard session.matches(profile: profile),
                      result[session.path] == nil else {
                    return
                }

                result[session.path] = session
            }

        var nextProgressByItemID: [String: RemoteComicReadingSession] = [:]
        var nextCacheAvailabilityByItemID: [String: RemoteComicCachedAvailability] = [:]

        for item in items {
            guard item.canOpenAsComic,
                  let reference = try? browsingService.makeComicFileReference(from: item) else {
                continue
            }

            if let session = sessionsByPath[reference.path] {
                nextProgressByItemID[item.id] = session
            }

            nextCacheAvailabilityByItemID[item.id] = browsingService.cachedAvailability(for: reference)
        }

        progressByItemID = nextProgressByItemID
        cacheAvailabilityByItemID = nextCacheAvailabilityByItemID
    }

    func refreshProgressState(for item: RemoteDirectoryItem) {
        recentSessions = recentSessionsForProfile()

        guard item.canOpenAsComic,
              let reference = try? browsingService.makeComicFileReference(from: item) else {
            progressByItemID.removeValue(forKey: item.id)
            cacheAvailabilityByItemID.removeValue(forKey: item.id)
            return
        }

        if let session = try? readingProgressStore.loadProgress(for: reference) {
            progressByItemID[item.id] = session
        } else {
            progressByItemID.removeValue(forKey: item.id)
        }

        cacheAvailabilityByItemID[item.id] = browsingService.cachedAvailability(for: reference)
    }

    private func scheduleProgressStateRefresh() {
        progressRefreshTask?.cancel()
        progressRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else {
                return
            }

            self.refreshProgressState()
            self.recentSessions = self.recentSessionsForProfile()
            self.progressRefreshTask = nil
        }
    }

    func progress(for item: RemoteDirectoryItem) -> RemoteComicReadingSession? {
        progressByItemID[item.id]
    }

    func cacheAvailability(for item: RemoteDirectoryItem) -> RemoteComicCachedAvailability {
        cacheAvailabilityByItemID[item.id] ?? .unavailable
    }

    func toggleCurrentFolderShortcut() {
        let normalizedPath = Self.normalizedShortcutPath(currentPath)
        let wasSaved = isCurrentFolderSaved

        do {
            if wasSaved {
                try folderShortcutStore.removeShortcut(
                    serverID: profile.id,
                    providerKind: profile.providerKind,
                    providerRootIdentifier: profile.normalizedProviderRootIdentifier,
                    path: normalizedPath
                )
            } else {
                try folderShortcutStore.upsertShortcut(
                    serverID: profile.id,
                    providerKind: profile.providerKind,
                    providerRootIdentifier: profile.normalizedProviderRootIdentifier,
                    path: normalizedPath,
                    title: currentFolderShortcutTitle
                )
            }
            refreshShortcutState()
            feedback = RemoteBrowserFeedbackState(
                title: wasSaved ? "Folder Removed" : "Folder Saved",
                message: wasSaved
                    ? "This remote folder was removed from Saved Folders."
                    : "This remote folder now appears in Browse > Saved Folders.",
                kind: .success,
                autoDismissAfter: 2.6
            )
        } catch {
            alert = RemoteAlertState(
                title: isCurrentFolderSaved ? "Failed to Remove Shortcut" : "Failed to Save Shortcut",
                message: error.localizedDescription
            )
        }
    }

    func refreshShortcutState() {
        isCurrentFolderSaved = folderShortcutStore.containsShortcut(
            for: profile.id,
            providerKind: profile.providerKind,
            providerRootIdentifier: profile.normalizedProviderRootIdentifier,
            path: Self.normalizedShortcutPath(currentPath)
        )
    }

    func importComic(
        _ item: RemoteDirectoryItem,
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) async {
        feedback = nil

        guard item.canOpenAsComic else {
            alert = RemoteAlertState(
                title: "Import Unavailable",
                message: "Only supported remote comic files can be imported."
            )
            return
        }

        guard let reference = try? browsingService.makeComicFileReference(from: item) else {
            alert = RemoteAlertState(
                title: "Import Unavailable",
                message: "This remote comic could not be prepared for import."
            )
            return
        }

        activeImportDescription = "Importing \(item.name)…"
        defer {
            activeImportDescription = nil
        }

        do {
            let downloadResult = try await browsingService.downloadComicFile(
                for: profile,
                reference: reference
            )
            guard importUsesCurrentRemoteCopy(downloadResult) else {
                alert = RemoteAlertState(
                    title: "Import Requires Current Remote Copy",
                    message: importUnavailableMessage(for: downloadResult)
                )
                return
            }

            defer {
                cleanupTemporaryImportDownloads([(reference, downloadResult)])
            }

            let importResult = try importedComicsImportService.importComicResources(
                from: [downloadResult.localFileURL],
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                destinationSelection: destinationSelection
            )
            presentImportResult(
                importResult,
                extraFailedItemNames: [],
                successTitle: "Imported to Library"
            )
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Import Comic",
                message: error.localizedDescription
            )
        }
    }

    func importDirectory(
        _ item: RemoteDirectoryItem,
        destinationSelection: LibraryImportDestinationSelection = .importedComics,
        scope: RemoteDirectoryImportScope = .includeSubfolders
    ) async {
        feedback = nil

        guard item.isDirectory else {
            alert = RemoteAlertState(
                title: "Import Unavailable",
                message: "Only remote folders can be imported recursively."
            )
            return
        }

        activeImportDescription = scope == .includeSubfolders ? "Scanning \(item.name)…" : "Checking \(item.name)…"
        do {
            let importableItems = try await importableComicItems(
                at: item.path,
                scope: scope
            )
            guard !importableItems.isEmpty else {
                activeImportDescription = nil
                alert = RemoteAlertState(
                    title: "Nothing to Import",
                    message: scope == .includeSubfolders
                        ? "No supported comic files were found in \(item.name) or its subfolders."
                        : "No supported comic files were found directly inside \(item.name)."
                )
                return
            }

            await importComicItems(
                importableItems,
                progressPrefix: "Importing \(item.name)",
                successTitle: "Folder Imported to Library",
                destinationSelection: destinationSelection
            )
        } catch {
            activeImportDescription = nil
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: error.localizedDescription
            )
        }
    }

    func importCurrentFolder(
        destinationSelection: LibraryImportDestinationSelection = .importedComics,
        scope: RemoteDirectoryImportScope = .includeSubfolders
    ) async {
        feedback = nil

        guard canImportCurrentFolderRecursively else {
            alert = RemoteAlertState(
                title: "Nothing to Import",
                message: "There are no supported comic files in this remote folder or its subfolders yet."
            )
            return
        }

        activeImportDescription = scope == .includeSubfolders ? "Scanning \(navigationTitle)…" : "Checking \(navigationTitle)…"
        do {
            let importableItems = try await importableComicItems(
                at: currentPath,
                scope: scope
            )
            guard !importableItems.isEmpty else {
                activeImportDescription = nil
                alert = RemoteAlertState(
                    title: "Nothing to Import",
                    message: scope == .includeSubfolders
                        ? "No supported comic files were found in this remote folder or its subfolders."
                        : "No supported comic files were found directly inside this remote folder."
                )
                return
            }

            await importComicItems(
                importableItems,
                progressPrefix: "Importing \(navigationTitle)",
                successTitle: "Folder Imported to Library",
                destinationSelection: destinationSelection
            )
        } catch {
            activeImportDescription = nil
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: error.localizedDescription
            )
        }
    }

    func importVisibleComics(
        _ items: [RemoteDirectoryItem],
        destinationSelection: LibraryImportDestinationSelection = .importedComics
    ) async {
        feedback = nil

        let visibleComics = items.filter(\.canOpenAsComic)
        guard !visibleComics.isEmpty else {
            alert = RemoteAlertState(
                title: "Nothing to Import",
                message: "There are no visible supported comic files in the current browser results."
            )
            return
        }

        await importComicItems(
            visibleComics,
            progressPrefix: "Importing visible comics",
            successTitle: "Visible Comics Imported",
            destinationSelection: destinationSelection
        )
    }

    func saveComicForOffline(
        _ item: RemoteDirectoryItem,
        forceRefresh: Bool = false
    ) async {
        feedback = nil

        guard item.canOpenAsComic else {
            alert = RemoteAlertState(
                title: "Offline Save Unavailable",
                message: "Only supported remote comic files can be saved for offline reading."
            )
            return
        }

        guard let reference = try? browsingService.makeComicFileReference(from: item) else {
            alert = RemoteAlertState(
                title: "Offline Save Unavailable",
                message: "This remote comic could not be prepared for offline reading."
            )
            return
        }

        activeImportDescription = forceRefresh
            ? "Refreshing downloaded copy…"
            : "Saving \(item.name)…"
        defer {
            activeImportDescription = nil
        }

        do {
            let result = try await browsingService.downloadComicFile(
                for: profile,
                reference: reference,
                forceRefresh: forceRefresh
            )
            refreshProgressState()
            feedback = RemoteBrowserFeedbackState(
                title: forceRefresh ? "Downloaded Copy Updated" : "Saved for Offline",
                message: offlineSaveMessage(for: item, result: result, forceRefresh: forceRefresh),
                kind: .success,
                autoDismissAfter: 3.2
            )
        } catch {
            alert = RemoteAlertState(
                title: "Failed to Save Offline Copy",
                message: error.localizedDescription
            )
        }
    }

    func saveComicsForOffline(_ items: [RemoteDirectoryItem]) async {
        feedback = nil

        let comics = items.filter(\.canOpenAsComic)
        guard !comics.isEmpty else {
            alert = RemoteAlertState(
                title: "Nothing to Save",
                message: "There are no supported remote comic files in the current results yet."
            )
            return
        }

        activeImportDescription = "Saving visible comics…"
        defer {
            activeImportDescription = nil
        }

        var failedNames: [String] = []
        let preparedDownloads = comics.compactMap { item -> (RemoteDirectoryItem, RemoteComicFileReference)? in
            guard let reference = try? browsingService.makeComicFileReference(from: item) else {
                failedNames.append(item.name)
                return nil
            }

            return (item, reference)
        }

        do {
            let outcomes = try await browsingService.downloadComicFiles(
                for: profile,
                references: preparedDownloads.map { $0.1 }
            )
            let itemNameByReferenceID = Dictionary(
                uniqueKeysWithValues: preparedDownloads.map { ($0.1.id, $0.0.name) }
            )

            var savedCount = 0
            var refreshedCount = 0

            for outcome in outcomes {
                if let result = outcome.result {
                    switch result.source {
                    case .downloaded:
                        savedCount += 1
                    case .cachedCurrent, .cachedFallback:
                        refreshedCount += 1
                    }
                } else {
                    failedNames.append(itemNameByReferenceID[outcome.reference.id] ?? outcome.reference.fileName)
                }
            }

            refreshProgressState()

            guard savedCount > 0 || refreshedCount > 0 else {
                alert = RemoteAlertState(
                    title: "Offline Save Failed",
                    message: "No visible comics could be saved for offline reading."
                )
                return
            }

            var segments: [String] = []
            if savedCount > 0 {
                segments.append("Saved \(savedCount) comic(s) to this device.")
            }
            if refreshedCount > 0 {
                let copyPhrase = refreshedCount == 1 ? "downloaded copy" : "downloaded copies"
                segments.append("Kept \(refreshedCount) existing \(copyPhrase) ready offline.")
            }
            if !failedNames.isEmpty {
                segments.append("Failed to save \(failedNames.count) item(s).")
            }

            feedback = RemoteBrowserFeedbackState(
                title: "Offline Copies Ready",
                message: segments.joined(separator: " "),
                kind: .success
            )
        } catch {
            alert = RemoteAlertState(
                title: "Offline Save Failed",
                message: error.localizedDescription
            )
        }
    }

    func removeOfflineCopy(for item: RemoteDirectoryItem) {
        feedback = nil

        guard item.canOpenAsComic else {
            return
        }

        guard let reference = try? browsingService.makeComicFileReference(from: item) else {
            alert = RemoteAlertState(
                title: "Remove Offline Copy Failed",
                message: "This remote comic could not be matched to a downloaded copy."
            )
            return
        }

        do {
            try browsingService.clearCachedComic(for: reference)
            refreshProgressState()
            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copy Removed",
                message: "\(item.name) was removed from this device.",
                kind: .info,
                autoDismissAfter: 2.6
            )
        } catch {
            alert = RemoteAlertState(
                title: "Remove Offline Copy Failed",
                message: error.localizedDescription
            )
        }
    }

    func removeOfflineCopies(for items: [RemoteDirectoryItem]) {
        feedback = nil

        let comics = items.filter(\.canOpenAsComic)
        guard !comics.isEmpty else {
            return
        }

        var removedCount = 0
        var failedNames: [String] = []

        for item in comics {
            guard let reference = try? browsingService.makeComicFileReference(from: item) else {
                failedNames.append(item.name)
                continue
            }

            guard browsingService.cachedAvailability(for: reference).hasLocalCopy else {
                continue
            }

            do {
                try browsingService.clearCachedComic(for: reference)
                removedCount += 1
            } catch {
                failedNames.append(item.name)
            }
        }

        refreshProgressState()

        guard removedCount > 0 else {
            if !failedNames.isEmpty {
                alert = RemoteAlertState(
                    title: "Remove Downloaded Copies Failed",
                    message: "No downloaded copies could be removed from this device."
                )
            }
            return
        }

        var message = "Removed \(removedCount) downloaded \(removedCount == 1 ? "copy" : "copies") from this device."
        if !failedNames.isEmpty {
            message += " Failed to remove \(failedNames.count) item(s)."
        }

        feedback = RemoteBrowserFeedbackState(
            title: "Downloaded Copies Removed",
            message: message,
            kind: .info,
            autoDismissAfter: 3.0
        )
    }

    static func lastBrowsedPath(for profile: RemoteServerProfile) -> String {
        initialPath(for: profile, explicitPath: nil)
    }

    static func clearRememberedPath(for profile: RemoteServerProfile) {
        UserDefaults.standard.removeObject(forKey: lastBrowsedPathStorageKey(for: profile))
    }

    func dismissFeedback() {
        feedback = nil
    }

    private static func initialPath(for profile: RemoteServerProfile, explicitPath: String?) -> String {
        if let explicitPath {
            return normalizedPath(explicitPath)
        }

        let rootPath = normalizedPath(profile.normalizedBaseDirectoryPath)
        let scopedKey = lastBrowsedPathStorageKey(for: profile)
        let legacyKey = "\(lastBrowsedPathKeyPrefix)\(profile.id.uuidString)"
        let storedPath = normalizedPath(
            UserDefaults.standard.string(forKey: scopedKey)
                ?? UserDefaults.standard.string(forKey: legacyKey)
                ?? rootPath
        )

        guard isPath(storedPath, withinRootPath: rootPath) else {
            return rootPath
        }

        return storedPath
    }

    private static func rememberLastBrowsedPath(_ path: String, for profile: RemoteServerProfile) {
        UserDefaults.standard.set(
            normalizedPath(path),
            forKey: lastBrowsedPathStorageKey(for: profile)
        )
    }

    private static func isPath(_ path: String, withinRootPath rootPath: String) -> Bool {
        let rootComponents = pathComponents(for: rootPath)
        let pathComponents = pathComponents(for: path)

        guard pathComponents.count >= rootComponents.count else {
            return false
        }

        return Array(pathComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        let collapsedPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard !collapsedPath.isEmpty else {
            return ""
        }

        return "/" + collapsedPath
    }

    private static func normalizedShortcutPath(_ rawPath: String) -> String {
        normalizedPath(rawPath)
    }

    private static func pathComponents(for path: String) -> [String] {
        normalizedPath(path)
            .split(separator: "/")
            .map(String.init)
    }

    private static func lastBrowsedPathStorageKey(for profile: RemoteServerProfile) -> String {
        "\(lastBrowsedPathKeyPrefix)\(profile.id.uuidString)|\(profile.remoteScopeKey)"
    }

    private func presentImportResult(
        _ result: ImportedComicsImportResult,
        extraFailedItemNames: [String],
        successTitle: String
    ) {
        let messageLines = result.completionMessageLines(
            extraFailedItemNames: extraFailedItemNames
        )

        guard !messageLines.isEmpty else {
            return
        }

        let primaryAction: RemoteAlertPrimaryAction? = (result.createdLibrary || result.hasImportedAnyComics)
            ? .openLibrary(result.importedDestinationID, 1)
            : nil

        if result.importedComicCount > 0 {
            AppHaptics.success()
            feedback = RemoteBrowserFeedbackState(
                title: successTitle,
                message: importFeedbackMessage(
                    from: result,
                    extraFailedItemNames: extraFailedItemNames
                ),
                kind: .success,
                primaryAction: primaryAction
            )
            return
        }

        alert = RemoteAlertState(
            title: "Import Finished with Warnings",
            message: messageLines.joined(separator: "\n"),
            primaryAction: primaryAction
        )
    }

    private func recentSessionsForProfile() -> [RemoteComicReadingSession] {
        ((try? readingProgressStore.loadSessions()) ?? []).filter { $0.matches(profile: profile) }
    }

    private func makeLoadIssue(from error: Error) -> RemoteBrowserLoadIssue {
        let normalizedError = error as? RemoteServerBrowsingError

        switch normalizedError {
        case .authenticationFailed:
            return RemoteBrowserLoadIssue(
                kind: .authentication,
                title: "Sign-in Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Open the server settings and verify the username or password, then try again."
            )
        case .connectionFailed:
            return RemoteBrowserLoadIssue(
                kind: .connection,
                title: "Server Unreachable",
                message: error.localizedDescription,
                recoverySuggestion: "Make sure this device can reach the remote server on the current network. You can still try opening a recently cached comic below."
            )
        case .shareUnavailable:
            return RemoteBrowserLoadIssue(
                kind: .shareUnavailable,
                title: "Location Unavailable",
                message: error.localizedDescription,
                recoverySuggestion: "The saved remote root may have changed or gone offline. Review the server settings, then refresh."
            )
        case .remotePathUnavailable:
            return RemoteBrowserLoadIssue(
                kind: .remotePathUnavailable,
                title: "Folder Not Found",
                message: error.localizedDescription,
                recoverySuggestion: "This folder may have been moved or deleted on the server. Try going up one level or return to the saved root folder."
            )
        case .accessDenied:
            return RemoteBrowserLoadIssue(
                kind: .accessDenied,
                title: "Access Denied",
                message: error.localizedDescription,
                recoverySuggestion: "The current credentials or permissions do not allow this folder. Try a different location or review the saved server settings."
            )
        case .invalidProfile, .providerIntegrationUnavailable, .unsupportedComicFile,
             .missingCredentials, .cacheMaintenanceFailed, .operationFailed, .none:
            return RemoteBrowserLoadIssue(
                kind: .generic,
                title: "Remote Browser Not Ready Yet",
                message: error.localizedDescription,
                recoverySuggestion: "Try refreshing this folder again. If the problem keeps coming back, return to the server list and review the saved connection."
            )
        }
    }

    private func importComicItems(
        _ items: [RemoteDirectoryItem],
        progressPrefix: String,
        successTitle: String,
        destinationSelection: LibraryImportDestinationSelection
    ) async {
        let sortedItems = items.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        var failedDownloadNames: [String] = []
        var stagedResultsForImport: [(RemoteComicFileReference, RemoteComicDownloadResult)] = []
        activeImportDescription = "\(progressPrefix)…"
        defer {
            activeImportDescription = nil
            cleanupTemporaryImportDownloads(stagedResultsForImport)
        }

        let preparedDownloads = sortedItems.compactMap { item -> (RemoteDirectoryItem, RemoteComicFileReference)? in
            guard let reference = try? browsingService.makeComicFileReference(from: item) else {
                failedDownloadNames.append(item.name)
                return nil
            }

            return (item, reference)
        }

        let downloadedFileURLs: [URL]
        do {
            let outcomes = try await browsingService.downloadComicFiles(
                for: profile,
                references: preparedDownloads.map { $0.1 }
            )
            let itemNameByReferenceID = Dictionary(
                uniqueKeysWithValues: preparedDownloads.map { ($0.1.id, $0.0.name) }
            )

            downloadedFileURLs = outcomes.compactMap { outcome in
                if let result = outcome.result {
                    guard importUsesCurrentRemoteCopy(result) else {
                        failedDownloadNames.append(itemNameByReferenceID[outcome.reference.id] ?? outcome.reference.fileName)
                        return nil
                    }

                    stagedResultsForImport.append((outcome.reference, result))
                    return result.localFileURL
                }

                failedDownloadNames.append(itemNameByReferenceID[outcome.reference.id] ?? outcome.reference.fileName)
                return nil
            }
        } catch {
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: error.localizedDescription
            )
            return
        }

        guard !downloadedFileURLs.isEmpty else {
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: "No remote comics could be downloaded for import."
            )
            return
        }

        do {
            let importResult = try importedComicsImportService.importComicResources(
                from: downloadedFileURLs,
                traverseDirectories: false,
                accessSecurityScopedResources: false,
                destinationSelection: destinationSelection
            )
            presentImportResult(
                importResult,
                extraFailedItemNames: failedDownloadNames,
                successTitle: successTitle
            )
        } catch {
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func importableComicItems(
        at path: String,
        scope: RemoteDirectoryImportScope
    ) async throws -> [RemoteDirectoryItem] {
        switch scope {
        case .visibleResults:
            return try await browsingService
                .listDirectory(for: profile, path: path)
                .filter(\.canOpenAsComic)
        case .currentFolderOnly:
            return try await browsingService
                .listDirectory(for: profile, path: path)
                .filter(\.canOpenAsComic)
        case .includeSubfolders:
            return try await browsingService.listComicFilesRecursively(
                for: profile,
                path: path
            )
        }
    }

    private func importFeedbackMessage(
        from result: ImportedComicsImportResult,
        extraFailedItemNames: [String]
    ) -> String {
        var segments: [String] = []

        if result.createdLibrary {
            segments.append("Added \(result.importedDestinationName).")
        }

        let comicWord = result.importedComicCount == 1 ? "comic" : "comics"
        segments.append("Imported \(result.importedComicCount) \(comicWord) into \(result.importedDestinationName).")

        if let scanSummary = result.scanSummary {
            segments.append(scanSummary.indexedSummaryLine + ".")
        } else if result.scanErrorMessage != nil {
            segments.append("Open the library and run Refresh to finish indexing the new files.")
        }

        if !result.unsupportedItemNames.isEmpty {
            let itemWord = result.unsupportedItemNames.count == 1 ? "item" : "items"
            segments.append("Skipped \(result.unsupportedItemNames.count) unsupported \(itemWord).")
        }

        let failedCount = Set(result.failedItemNames + extraFailedItemNames).count
        if failedCount > 0 {
            segments.append("Failed to import \(failedCount) item(s).")
        }

        return segments.joined(separator: " ")
    }

    private func importUsesCurrentRemoteCopy(_ result: RemoteComicDownloadResult) -> Bool {
        switch result.source {
        case .downloaded, .cachedCurrent:
            return true
        case .cachedFallback:
            return false
        }
    }

    private func importUnavailableMessage(for result: RemoteComicDownloadResult) -> String {
        switch result.source {
        case .downloaded, .cachedCurrent:
            return "The selected remote comic is ready to import."
        case .cachedFallback(let message):
            return "The latest remote copy could not be fetched, so importing an older downloaded copy into the library was skipped to keep library data in sync.\n\n\(message)"
        }
    }

    private func cleanupTemporaryImportDownloads(
        _ stagedResults: [(RemoteComicFileReference, RemoteComicDownloadResult)]
    ) {
        for (reference, result) in stagedResults {
            guard case .downloaded = result.source else {
                continue
            }

            try? browsingService.clearCachedComic(for: reference)
        }
    }

    private func offlineSaveMessage(
        for item: RemoteDirectoryItem,
        result: RemoteComicDownloadResult,
        forceRefresh: Bool
    ) -> String {
        switch result.source {
        case .downloaded:
            return forceRefresh
                ? "Downloaded the latest copy of \(item.name) to this device."
                : "Saved \(item.name) to this device for offline reading."
        case .cachedCurrent:
            return "\(item.name) is already saved on this device and ready offline."
        case .cachedFallback:
            return "A downloaded copy of \(item.name) is already available on this device."
        }
    }
}
