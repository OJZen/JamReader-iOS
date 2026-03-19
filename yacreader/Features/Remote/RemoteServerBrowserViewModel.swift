import Combine
import Foundation

@MainActor
final class RemoteServerBrowserViewModel: ObservableObject {
    private static let lastBrowsedPathKeyPrefix = "remoteServerBrowser.lastPath."

    @Published private(set) var items: [RemoteDirectoryItem] = []
    @Published private(set) var progressByItemID: [String: RemoteComicReadingSession] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var activeImportDescription: String?
    @Published var alert: RemoteAlertState?

    let profile: RemoteServerProfile
    let currentPath: String
    let capabilities: RemoteServerBrowserCapabilities

    private let browsingService: RemoteServerBrowsingService
    private let readingProgressStore: RemoteReadingProgressStore
    private let importedComicsImportService: ImportedComicsImportService
    private var hasLoaded = false

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        browsingService: RemoteServerBrowsingService,
        readingProgressStore: RemoteReadingProgressStore,
        importedComicsImportService: ImportedComicsImportService
    ) {
        self.profile = profile
        self.currentPath = Self.initialPath(for: profile, explicitPath: currentPath)
        self.capabilities = browsingService.capabilities(for: profile.providerKind)
        self.browsingService = browsingService
        self.readingProgressStore = readingProgressStore
        self.importedComicsImportService = importedComicsImportService
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
        if let loadErrorMessage {
            return loadErrorMessage
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
            loadErrorMessage = nil
            Self.rememberLastBrowsedPath(currentPath, for: profile)
        } catch {
            items = []
            progressByItemID = [:]
            loadErrorMessage = error.localizedDescription
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
    }

    func progress(for item: RemoteDirectoryItem) -> RemoteComicReadingSession? {
        progressByItemID[item.id]
    }

    func importComic(_ item: RemoteDirectoryItem) async {
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
                accessSecurityScopedResources: false
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

    func importDirectory(_ item: RemoteDirectoryItem) async {
        guard item.isDirectory else {
            alert = RemoteAlertState(
                title: "Import Unavailable",
                message: "Only remote folders can be imported recursively."
            )
            return
        }

        activeImportDescription = "Scanning \(item.name)…"
        do {
            let nestedComicFiles = try await browsingService.listComicFilesRecursively(
                for: profile,
                path: item.path
            )
            guard !nestedComicFiles.isEmpty else {
                activeImportDescription = nil
                alert = RemoteAlertState(
                    title: "Nothing to Import",
                    message: "No supported comic files were found in \(item.name) or its subfolders."
                )
                return
            }

            await importComicItems(
                nestedComicFiles,
                progressPrefix: "Importing \(item.name)",
                successTitle: "Folder Imported to Library"
            )
        } catch {
            activeImportDescription = nil
            alert = RemoteAlertState(
                title: "Folder Import Failed",
                message: error.localizedDescription
            )
        }
    }

    func importCurrentFolderRecursively() async {
        guard canImportCurrentFolderRecursively else {
            alert = RemoteAlertState(
                title: "Nothing to Import",
                message: "There are no supported comic files in this remote folder or its subfolders yet."
            )
            return
        }

        activeImportDescription = "Scanning \(navigationTitle)…"
        do {
            let nestedComicFiles = try await browsingService.listComicFilesRecursively(
                for: profile,
                path: currentPath
            )
            guard !nestedComicFiles.isEmpty else {
                activeImportDescription = nil
                alert = RemoteAlertState(
                    title: "Nothing to Import",
                    message: "No supported comic files were found in this remote folder or its subfolders."
                )
                return
            }

            await importComicItems(
                nestedComicFiles,
                progressPrefix: "Importing \(navigationTitle)",
                successTitle: "Folder Imported to Library"
            )
        } catch {
            activeImportDescription = nil
            alert = RemoteAlertState(
                title: "Folder Import Failed",
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

        alert = RemoteAlertState(
            title: result.importedComicCount > 0 ? successTitle : "Import Finished with Warnings",
            message: messageLines.joined(separator: "\n")
        )
    }

    private func importComicItems(
        _ items: [RemoteDirectoryItem],
        progressPrefix: String,
        successTitle: String
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
                accessSecurityScopedResources: false
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
}
