import Combine
import Foundation

@MainActor
final class RemoteServerBrowserViewModel: ObservableObject {
    private static let lastBrowsedPathKeyPrefix = "remoteServerBrowser.lastPath."

    @Published private(set) var items: [RemoteDirectoryItem] = []
    @Published private(set) var progressByItemID: [String: RemoteComicReadingSession] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    @Published var alert: RemoteAlertState?

    let profile: RemoteServerProfile
    let currentPath: String
    let capabilities: RemoteServerBrowserCapabilities

    private let browsingService: RemoteServerBrowsingService
    private let readingProgressStore: RemoteReadingProgressStore
    private var hasLoaded = false

    init(
        profile: RemoteServerProfile,
        currentPath: String? = nil,
        browsingService: RemoteServerBrowsingService,
        readingProgressStore: RemoteReadingProgressStore
    ) {
        self.profile = profile
        self.currentPath = Self.initialPath(for: profile, explicitPath: currentPath)
        self.capabilities = browsingService.capabilities(for: profile.providerKind)
        self.browsingService = browsingService
        self.readingProgressStore = readingProgressStore
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
}
