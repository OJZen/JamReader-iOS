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

    var summaryText: String {
        if let loadIssue {
            return loadIssue.message
        }

        if items.isEmpty {
            return "No folders or supported comic files are visible in this remote location."
        }

        let folderCount = directories.count
        let comicCount = comicFiles.count
        let hiddenCount = unsupportedFileCount

        if hiddenCount > 0 {
            return "\(folderCount) folders and \(comicCount) comic files are visible here. \(hiddenCount) unsupported files are hidden."
        }

        return "\(folderCount) folders and \(comicCount) comic files are visible here."
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

    var recoverySession: RemoteComicReadingSession? {
        recentSessions.first { browsingService.cachedAvailability(for: $0.comicFileReference).hasLocalCopy }
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
            refreshProgressState()
            recentSessions = recentSessionsForProfile()
            loadIssue = nil
            Self.rememberLastBrowsedPath(currentPath, for: profile)
            refreshShortcutState()
        } catch {
            items = []
            progressByItemID = [:]
            cacheAvailabilityByItemID = [:]
            recentSessions = recentSessionsForProfile()
            loadIssue = makeLoadIssue(from: error)
            refreshShortcutState()
        }
    }

    func refreshProgressState() {
        progressByItemID = items.reduce(into: [:]) { result, item in
            guard item.canOpenAsComic,
                  let reference = try? browsingService.makeComicFileReference(from: item),
                  let progress = try? readingProgressStore.loadProgress(for: reference)
            else {
                return
            }

            result[item.id] = progress
        }

        cacheAvailabilityByItemID = items.reduce(into: [:]) { result, item in
            guard item.canOpenAsComic,
                  let reference = try? browsingService.makeComicFileReference(from: item)
            else {
                return
            }

            result[item.id] = browsingService.cachedAvailability(for: reference)
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
                    path: normalizedPath
                )
            } else {
                try folderShortcutStore.upsertShortcut(
                    serverID: profile.id,
                    path: normalizedPath,
                    title: currentFolderShortcutTitle
                )
            }
            refreshShortcutState()
            feedback = RemoteBrowserFeedbackState(
                title: wasSaved ? "Folder Removed" : "Folder Saved",
                message: wasSaved
                    ? "This SMB folder was removed from Saved Folders."
                    : "This SMB folder now appears in Browse > Saved Folders.",
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

        var savedCount = 0
        var refreshedCount = 0
        var failedNames: [String] = []

        for (index, item) in comics.enumerated() {
            activeImportDescription = "Saving visible comics… \(index + 1) of \(comics.count)"

            guard let reference = try? browsingService.makeComicFileReference(from: item) else {
                failedNames.append(item.name)
                continue
            }

            do {
                let result = try await browsingService.downloadComicFile(
                    for: profile,
                    reference: reference
                )
                switch result.source {
                case .downloaded:
                    savedCount += 1
                case .cachedCurrent, .cachedFallback:
                    refreshedCount += 1
                }
            } catch {
                failedNames.append(item.name)
            }
        }

        activeImportDescription = nil
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

    static func lastBrowsedPath(for profile: RemoteServerProfile) -> String {
        initialPath(for: profile, explicitPath: nil)
    }

    static func clearRememberedPath(for profile: RemoteServerProfile) {
        UserDefaults.standard.removeObject(forKey: lastBrowsedPathStorageKey(for: profile.id))
    }

    func dismissFeedback() {
        feedback = nil
    }

    private static func initialPath(for profile: RemoteServerProfile, explicitPath: String?) -> String {
        if let explicitPath {
            return normalizedPath(explicitPath)
        }

        let rootPath = normalizedPath(profile.normalizedBaseDirectoryPath)
        let storedPath = normalizedPath(
            UserDefaults.standard.string(forKey: lastBrowsedPathStorageKey(for: profile.id)) ?? rootPath
        )

        guard isPath(storedPath, withinRootPath: rootPath) else {
            return rootPath
        }

        return storedPath
    }

    private static func rememberLastBrowsedPath(_ path: String, for profile: RemoteServerProfile) {
        UserDefaults.standard.set(
            normalizedPath(path),
            forKey: lastBrowsedPathStorageKey(for: profile.id)
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

    private static func lastBrowsedPathStorageKey(for serverID: UUID) -> String {
        "\(lastBrowsedPathKeyPrefix)\(serverID.uuidString)"
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
        ((try? readingProgressStore.loadSessions()) ?? []).filter { $0.serverID == profile.id }
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
                recoverySuggestion: "Make sure this device can reach the SMB server on the current network. You can still try opening a recently cached comic below."
            )
        case .shareUnavailable:
            return RemoteBrowserLoadIssue(
                kind: .shareUnavailable,
                title: "Share Unavailable",
                message: error.localizedDescription,
                recoverySuggestion: "The share name may have changed or gone offline. Review the saved SMB server settings, then refresh."
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
                recoverySuggestion: "The current credentials or permissions do not allow this folder. Try a different location or review the saved SMB server settings."
            )
        case .invalidProfile, .providerIntegrationUnavailable, .unsupportedComicFile,
             .missingCredentials, .cacheMaintenanceFailed, .operationFailed, .none:
            return RemoteBrowserLoadIssue(
                kind: .generic,
                title: "Remote Browser Not Ready Yet",
                message: error.localizedDescription,
                recoverySuggestion: "Try refreshing this folder again. If the problem keeps coming back, return to the SMB server list and review the saved connection."
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

        var downloadedFileURLs: [URL] = []
        var failedDownloadNames: [String] = []

        for (index, item) in sortedItems.enumerated() {
            activeImportDescription = "\(progressPrefix)… \(index + 1) of \(sortedItems.count)"

            guard let reference = try? browsingService.makeComicFileReference(from: item) else {
                failedDownloadNames.append(item.name)
                continue
            }

            do {
                let downloadResult = try await browsingService.downloadComicFile(
                    for: profile,
                    reference: reference
                )
                downloadedFileURLs.append(downloadResult.localFileURL)
            } catch {
                failedDownloadNames.append(item.name)
            }
        }

        defer {
            activeImportDescription = nil
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
