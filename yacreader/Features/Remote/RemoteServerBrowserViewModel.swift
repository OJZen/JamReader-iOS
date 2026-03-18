import Combine
import Foundation

@MainActor
final class RemoteServerBrowserViewModel: ObservableObject {
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
        self.currentPath = currentPath ?? profile.normalizedBaseDirectoryPath
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
}
