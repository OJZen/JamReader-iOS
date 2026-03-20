import Combine
import SwiftUI

private enum RemoteOfflineShelfSortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recently Opened"
        case .title:
            return "Title"
        case .server:
            return "Server"
        }
    }

    var shortTitle: String {
        switch self {
        case .recent:
            return "Recent"
        case .title:
            return "Title"
        case .server:
            return "Server"
        }
    }

    var systemImageName: String {
        switch self {
        case .recent:
            return "clock.arrow.circlepath"
        case .title:
            return "textformat.abc"
        case .server:
            return "server.rack"
        }
    }

    func sort(_ entries: [RemoteOfflineComicEntry]) -> [RemoteOfflineComicEntry] {
        switch self {
        case .recent:
            return entries.sorted { lhs, rhs in
                lhs.session.lastTimeOpened > rhs.session.lastTimeOpened
            }
        case .title:
            return entries.sorted { lhs, rhs in
                lhs.session.displayName.localizedStandardCompare(rhs.session.displayName) == .orderedAscending
            }
        case .server:
            return entries.sorted { lhs, rhs in
                let comparison = lhs.profile.name.localizedStandardCompare(rhs.profile.name)
                if comparison == .orderedSame {
                    return lhs.session.displayName.localizedStandardCompare(rhs.session.displayName) == .orderedAscending
                }

                return comparison == .orderedAscending
            }
        }
    }
}

private enum RemoteOfflineShelfFilter: String, CaseIterable, Identifiable {
    case all
    case current
    case stale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .current:
            return "Offline Ready"
        case .stale:
            return "Older Copies"
        }
    }

    func includes(_ entry: RemoteOfflineComicEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .current:
            return entry.availability.kind == .current
        case .stale:
            return entry.availability.kind == .stale
        }
    }
}

private enum RemoteOfflineShelfNavigationRequest: Identifiable, Hashable {
    case folder(RemoteServerProfile, String)

    var id: String {
        switch self {
        case .folder(let profile, let path):
            return "folder:\(profile.id.uuidString):\(path)"
        }
    }
}

@MainActor
final class RemoteOfflineShelfViewModel: ObservableObject {
    @Published private(set) var entries: [RemoteOfflineComicEntry] = []
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
    @Published private(set) var isLoading = false
    @Published var feedback: RemoteBrowserFeedbackState?
    @Published var alert: BrowseHomeAlert?

    private let remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.remoteOfflineLibrarySnapshotStore = dependencies.remoteOfflineLibrarySnapshotStore
        self.remoteServerBrowsingService = dependencies.remoteServerBrowsingService
    }

    var summaryTitle: String {
        switch entries.count {
        case 0:
            return "No offline comics yet"
        case 1:
            return "1 offline-ready comic"
        default:
            return "\(entries.count) offline-ready comics"
        }
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
            try rebuildEntries()
            alert = nil
        } catch {
            entries = []
            cacheSummary = .empty
            alert = BrowseHomeAlert(
                title: "Offline Shelf Unavailable",
                message: error.localizedDescription
            )
        }
    }

    func refreshDownloadedCopy(for entry: RemoteOfflineComicEntry) async {
        feedback = nil

        await activeOperation {
            let result = try await remoteServerBrowsingService.downloadComicFile(
                for: entry.profile,
                reference: entry.session.comicFileReference,
                forceRefresh: true
            )
            try rebuildEntries()

            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copy Updated",
                message: refreshFeedbackMessage(for: entry, result: result),
                kind: .success,
                autoDismissAfter: 3.2
            )
        }
    }

    func removeDownloadedCopy(for entry: RemoteOfflineComicEntry) {
        feedback = nil

        do {
            try remoteServerBrowsingService.clearCachedComic(for: entry.session.comicFileReference)
            try rebuildEntries()
            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copy Removed",
                message: "\(entry.session.displayName) was removed from this device.",
                kind: .info,
                autoDismissAfter: 2.6
            )
        } catch {
            alert = BrowseHomeAlert(
                title: "Remove Downloaded Copy Failed",
                message: error.localizedDescription
            )
        }
    }

    func clearDownloadedCopies(for profile: RemoteServerProfile, removedCount: Int) {
        feedback = nil

        do {
            try remoteServerBrowsingService.clearCachedComics(for: profile)
            try rebuildEntries()
            let copyWord = removedCount == 1 ? "copy" : "copies"
            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copies Removed",
                message: "Removed \(removedCount) downloaded \(copyWord) from \(profile.name).",
                kind: .info,
                autoDismissAfter: 3.0
            )
        } catch {
            alert = BrowseHomeAlert(
                title: "Clear Downloaded Copies Failed",
                message: error.localizedDescription
            )
        }
    }

    func downloadedCopyCount(for profile: RemoteServerProfile) -> Int {
        entries.filter { $0.profile.id == profile.id }.count
    }

    private func activeOperation(
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
        } catch {
            try? rebuildEntries()
            alert = BrowseHomeAlert(
                title: "Offline Shelf Action Failed",
                message: error.localizedDescription
            )
        }
    }

    private func rebuildEntries() throws {
        let snapshot = try remoteOfflineLibrarySnapshotStore.loadSnapshot()
        entries = snapshot.offlineEntries
        cacheSummary = snapshot.cacheSummary
    }

    private func refreshFeedbackMessage(
        for entry: RemoteOfflineComicEntry,
        result: RemoteComicDownloadResult
    ) -> String {
        switch result.source {
        case .downloaded:
            return "Downloaded the latest copy of \(entry.session.displayName) to this device."
        case .cachedCurrent:
            return "\(entry.session.displayName) is already current on this device."
        case .cachedFallback(let message):
            return message
        }
    }
}

struct RemoteOfflineShelfView: View {
    let dependencies: AppDependencies
    let focusedProfile: RemoteServerProfile?

    @StateObject private var viewModel: RemoteOfflineShelfViewModel
    @State private var searchText = ""
    @State private var sortMode: RemoteOfflineShelfSortMode = .recent
    @State private var filterMode: RemoteOfflineShelfFilter = .all
    @State private var navigationRequest: RemoteOfflineShelfNavigationRequest?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var pendingRemovalEntry: RemoteOfflineComicEntry?
    @State private var pendingServerClearProfile: RemoteServerProfile?
    @State private var pendingServerClearCount = 0

    init(
        dependencies: AppDependencies,
        focusedProfile: RemoteServerProfile? = nil
    ) {
        self.dependencies = dependencies
        self.focusedProfile = focusedProfile
        _viewModel = StateObject(
            wrappedValue: RemoteOfflineShelfViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        List {
            Section {
                heroCard
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if scopedEntries.isEmpty, !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Offline Comics",
                        systemImage: "arrow.down.circle",
                        description: Text(
                            focusedProfile == nil
                                ? "Save a remote comic offline to keep it on this device."
                                : "Save comics from this server offline."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else if displayedEntries.isEmpty, !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        emptyResultsTitle,
                        systemImage: "magnifyingglass",
                        description: Text(emptyResultsDescription)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(displayedSections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            NavigationLink {
                                RemoteComicLoadingView(
                                    profile: entry.profile,
                                    item: entry.session.directoryItem,
                                    dependencies: dependencies,
                                    openMode: .preferLocalCache
                                )
                            } label: {
                                RemoteOfflineComicCard(
                                    session: entry.session,
                                    profile: entry.profile,
                                    availability: entry.availability,
                                    showsNavigationIndicator: true,
                                    showsServerName: false,
                                    trailingAccessoryReservedWidth: 46
                                )
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                RemoteOfflineShelfItemActionMenuButton(
                                    onBrowseFolder: {
                                        navigationRequest = .folder(
                                            entry.profile,
                                            entry.session.parentDirectoryPath
                                        )
                                    },
                                    onRefreshDownloadedCopy: {
                                        Task<Void, Never> {
                                            await viewModel.refreshDownloadedCopy(for: entry)
                                        }
                                    },
                                    onDeleteDownloadedCopy: {
                                        pendingRemovalEntry = entry
                                    }
                                )
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                            }
                        }
                    } header: {
                        if focusedProfile == nil {
                            sectionHeader(for: section)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(background)
        .navigationTitle("Offline Shelf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort") {
                        ForEach(RemoteOfflineShelfSortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                HStack {
                                    Label(mode.title, systemImage: mode.systemImageName)
                                    if sortMode == mode {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search downloaded remote comics"
        )
        .safeAreaInset(edge: .bottom) {
            if let feedback = viewModel.feedback {
                RemoteBrowserFeedbackCard(
                    feedback: feedback,
                    onPrimaryAction: nil,
                    onDismiss: {
                        viewModel.feedback = nil
                    }
                )
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: viewModel.feedback?.id) { _, _ in
            scheduleFeedbackDismissalIfNeeded()
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
        }
        .navigationDestination(item: $navigationRequest) { request in
            switch request {
            case .folder(let profile, let path):
                RemoteServerBrowserView(
                    profile: profile,
                    currentPath: path,
                    dependencies: dependencies
                )
            }
        }
        .confirmationDialog(
            "Delete downloaded copy?",
            isPresented: Binding(
                get: { pendingRemovalEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemovalEntry = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let entry = pendingRemovalEntry {
                Button("Delete Downloaded Copy", role: .destructive) {
                    viewModel.removeDownloadedCopy(for: entry)
                    pendingRemovalEntry = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingRemovalEntry = nil
            }
        } message: {
            if let entry = pendingRemovalEntry {
                Text("Only the downloaded copy of \"\(entry.session.displayName)\" will be removed from this device. Reading progress will stay intact.")
            }
        }
        .confirmationDialog(
            "Delete all downloaded copies for this server?",
            isPresented: Binding(
                get: { pendingServerClearProfile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingServerClearProfile = nil
                        pendingServerClearCount = 0
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let profile = pendingServerClearProfile {
                Button("Delete Server Copies", role: .destructive) {
                    viewModel.clearDownloadedCopies(
                        for: profile,
                        removedCount: pendingServerClearCount
                    )
                    pendingServerClearProfile = nil
                    pendingServerClearCount = 0
                }
            }

            Button("Cancel", role: .cancel) {
                pendingServerClearProfile = nil
                pendingServerClearCount = 0
            }
        } message: {
            if let profile = pendingServerClearProfile {
                Text("This removes \(pendingServerClearCount) downloaded copies for \(profile.name) from this device. Remote files and reading progress stay intact.")
            }
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var displayedEntries: [RemoteOfflineComicEntry] {
        let filtered: [RemoteOfflineComicEntry]
        if trimmedSearchText.isEmpty {
            filtered = scopedEntries
        } else {
            filtered = scopedEntries.filter { entry in
                entry.session.displayName.localizedStandardContains(trimmedSearchText)
                    || entry.profile.name.localizedStandardContains(trimmedSearchText)
                    || entry.session.path.localizedStandardContains(trimmedSearchText)
            }
        }

        return sortMode.sort(filtered.filter { filterMode.includes($0) })
    }

    private var displayedSections: [RemoteOfflineShelfSection] {
        let grouped = Dictionary(grouping: displayedEntries) { $0.profile.id }

        return grouped.values
            .map { entries in
                RemoteOfflineShelfSection(
                    profile: entries[0].profile,
                    entries: entries
                )
            }
            .sorted {
                $0.profile.name.localizedStandardCompare($1.profile.name) == .orderedAscending
            }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var scopedEntries: [RemoteOfflineComicEntry] {
        if let focusedProfile {
            return viewModel.entries.filter { $0.profile.id == focusedProfile.id }
        }

        return viewModel.entries
    }

    private var emptyResultsTitle: String {
        if !trimmedSearchText.isEmpty {
            return "No Matches"
        }

        switch filterMode {
        case .all:
            return "No Offline Comics"
        case .current:
            return "No Offline-Ready Comics"
        case .stale:
            return "No Older Copies"
        }
    }

    private var emptyResultsDescription: String {
        if !trimmedSearchText.isEmpty {
            return "No matches for \"\(trimmedSearchText)\"."
        }

        switch filterMode {
        case .all:
            return "No downloaded comics on this device."
        case .current:
            return "No current local copies."
        case .stale:
            return "No older local copies."
        }
    }

    private var heroCard: some View {
        SectionSummaryCard(
            title: summaryTitle,
            badges: summaryBadges,
            titleFont: .title2.bold()
        ) {
            Picker("Filter", selection: $filterMode) {
                ForEach(RemoteOfflineShelfFilter.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryBadges: [StatusBadgeItem] {
        var badges = [
            StatusBadgeItem(
                title: viewModel.cacheSummary.isEmpty ? "Empty" : viewModel.cacheSummary.summaryText,
                tint: .blue
            ),
            StatusBadgeItem(title: sortMode.shortTitle, tint: .teal),
            StatusBadgeItem(title: filterMode.title, tint: .orange)
        ]

        if !trimmedSearchText.isEmpty {
            badges.append(StatusBadgeItem(title: "Searching", tint: .pink))
        }

        return badges
    }

    @ViewBuilder
    private func sectionHeader(for section: RemoteOfflineShelfSection) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(section.profile.name)
                    .font(.subheadline.weight(.semibold))

                AdaptiveStatusBadgeGroup(
                    badges: section.headerBadges,
                    horizontalSpacing: 6,
                    verticalSpacing: 6
                )
            }

            Spacer(minLength: 10)

            Button(role: .destructive) {
                pendingServerClearProfile = section.profile
                pendingServerClearCount = viewModel.downloadedCopyCount(for: section.profile)
            } label: {
                Label("Clear Server", systemImage: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .textCase(nil)
    }

    private var summaryTitle: String {
        let count = scopedEntries.count
        if let focusedProfile {
            switch count {
            case 0:
                return "No offline comics for \(focusedProfile.name)"
            case 1:
                return "1 offline comic for \(focusedProfile.name)"
            default:
                return "\(count) offline comics for \(focusedProfile.name)"
            }
        }

        return viewModel.summaryTitle
    }

    private var background: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }

    private func scheduleFeedbackDismissalIfNeeded() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil

        guard let feedback = viewModel.feedback,
              let autoDismissAfter = feedback.autoDismissAfter
        else {
            return
        }

        feedbackDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(autoDismissAfter * 1_000_000_000))
                guard !Task.isCancelled else {
                    return
                }

                if viewModel.feedback?.id == feedback.id {
                    viewModel.feedback = nil
                }
            } catch {
                // Ignore cancellation.
            }
        }
    }
}

private struct RemoteOfflineShelfItemActionMenuButton: View {
    let onBrowseFolder: () -> Void
    let onRefreshDownloadedCopy: () -> Void
    let onDeleteDownloadedCopy: () -> Void

    var body: some View {
        RemoteCardActionMenuButton(accessibilityLabel: "Offline Comic Actions") {
            Button(action: onBrowseFolder) {
                Label("Browse Source Folder", systemImage: "folder")
            }

            Button(action: onRefreshDownloadedCopy) {
                Label("Refresh Downloaded Copy", systemImage: "arrow.clockwise.circle")
            }

            Button(role: .destructive, action: onDeleteDownloadedCopy) {
                Label("Delete Downloaded Copy", systemImage: "trash")
            }
        }
    }
}

private struct RemoteOfflineShelfSection: Identifiable {
    let profile: RemoteServerProfile
    let entries: [RemoteOfflineComicEntry]

    var id: UUID {
        profile.id
    }

    var headerBadges: [StatusBadgeItem] {
        let currentCount = entries.filter { $0.availability.kind == .current }.count
        let staleCount = entries.filter { $0.availability.kind == .stale }.count

        var badges = [StatusBadgeItem]()

        if currentCount > 0 {
            badges.append(
                StatusBadgeItem(
                    title: currentCount == 1 ? "1 ready" : "\(currentCount) ready",
                    tint: .blue
                )
            )
        }

        if staleCount > 0 {
            badges.append(
                StatusBadgeItem(
                    title: staleCount == 1 ? "1 older" : "\(staleCount) older",
                    tint: .orange
                )
            )
        }

        if badges.isEmpty {
            badges.append(
                StatusBadgeItem(
                    title: entries.count == 1 ? "1 copy" : "\(entries.count) copies",
                    tint: .teal
                )
            )
        }

        return badges
    }
}
