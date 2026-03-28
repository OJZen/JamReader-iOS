import Combine
import SwiftUI
import UIKit

private enum RemoteOfflineShelfLayoutMetrics {
    static let horizontalInset: CGFloat = 12
}

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
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private var hasLoaded = false

    init(dependencies: AppDependencies) {
        self.remoteOfflineLibrarySnapshotStore = dependencies.remoteOfflineLibrarySnapshotStore
        self.remoteServerBrowsingService = dependencies.remoteServerBrowsingService
        self.remoteReadingProgressStore = dependencies.remoteReadingProgressStore
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
            try remoteReadingProgressStore.deleteSessions(for: profile)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            try rebuildEntries()
            let copyWord = removedCount == 1 ? "copy" : "copies"
            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copies Removed",
                message: "Removed \(removedCount) downloaded \(copyWord) from \(profile.name) and cleared its browsing history.",
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
    @State private var presentedEntry: RemoteOfflineComicEntry?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?

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
            summarySection

            if scopedEntries.isEmpty, !viewModel.isLoading {
                Section {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "No Offline Comics",
                        description: focusedProfile == nil
                            ? "Save a remote comic offline to keep it on this device."
                            : "Save comics from this server offline."
                    )
                    .padding(.vertical, 28)
                }
            } else if displayedEntries.isEmpty, !viewModel.isLoading {
                Section {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: emptyResultsTitle,
                        description: emptyResultsDescription
                    )
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(displayedSections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            HeroTapButton { frame in
                                prepareHeroTransition(for: entry, fallbackFrame: frame)
                                presentedEntry = entry
                            } label: {
                                RemoteInsetListRowCard(contentPadding: 12) {
                                    RemoteOfflineComicCard(
                                        session: entry.session,
                                        profile: entry.profile,
                                        availability: entry.availability,
                                        browsingService: dependencies.remoteServerBrowsingService,
                                        heroSourceID: entry.session.directoryItem.id,
                                        showsNavigationIndicator: false,
                                        showsServerName: false
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .insetCardListRow(horizontalInset: RemoteOfflineShelfLayoutMetrics.horizontalInset)
                            .contextMenu {
                                offlineShelfItemActionMenuContent(for: entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                offlineShelfItemSwipeActions(for: entry)
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
        .background(readerPresenter)
        .navigationTitle("Offline Shelf")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Filter") {
                        ForEach(RemoteOfflineShelfFilter.allCases) { mode in
                            Button {
                                filterMode = mode
                            } label: {
                                selectionMenuLabel(
                                    title: mode.title,
                                    systemImage: mode == .all
                                        ? "line.3.horizontal.decrease.circle"
                                        : "line.3.horizontal.decrease.circle.fill",
                                    isSelected: filterMode == mode
                                )
                            }
                        }
                    }

                    Section("Sort") {
                        ForEach(RemoteOfflineShelfSortMode.allCases) { mode in
                            Button {
                                sortMode = mode
                            } label: {
                                selectionMenuLabel(
                                    title: mode.title,
                                    systemImage: mode.systemImageName,
                                    isSelected: sortMode == mode
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Browse Options")
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

    @ViewBuilder
    private var readerPresenter: some View {
        HeroReaderPresenter(
            item: $presentedEntry,
            sourceFrame: heroSourceFrame,
            previewImage: heroPreviewImage,
            onDismiss: {
                heroSourceFrame = .zero
                heroPreviewImage = nil
            }
        ) { entry in
            RemoteComicLoadingView(
                profile: entry.profile,
                item: entry.session.directoryItem,
                dependencies: dependencies,
                openMode: .preferLocalCache
            )
        }
    }

    @MainActor
    private func prepareHeroTransition(for entry: RemoteOfflineComicEntry, fallbackFrame: CGRect) {
        let item = entry.session.directoryItem
        let registeredFrame = HeroSourceRegistry.shared.frame(for: item.id)
        heroSourceFrame = registeredFrame == .zero ? fallbackFrame : registeredFrame
        heroPreviewImage = RemoteComicThumbnailPipeline.shared.cachedTransitionImage(
            for: item,
            browsingService: dependencies.remoteServerBrowsingService
        )
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

    private var summarySection: some View {
        Section {
            InsetCard(
                cornerRadius: 24,
                contentPadding: 16,
                backgroundColor: Color(.systemBackground),
                strokeOpacity: 0.04
            ) {
                SummaryMetricGroup(
                    metrics: summaryMetrics,
                    style: .compactValue,
                    horizontalSpacing: 10,
                    verticalSpacing: 8
                )

                RemoteInlineMetadataLine(
                    items: summaryMetadataItems,
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                )

                Label(summaryDescription, systemImage: "arrow.down.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .insetCardListRow(
                horizontalInset: RemoteOfflineShelfLayoutMetrics.horizontalInset,
                top: 14,
                bottom: 10
            )
        }
    }

    private var summaryMetrics: [SummaryMetricItem] {
        let readyCount = scopedEntries.filter { $0.availability.kind == .current }.count
        let olderCount = scopedEntries.filter { $0.availability.kind == .stale }.count

        var metrics = [
            SummaryMetricItem(
                title: "Copies",
                value: "\(scopedEntries.count)",
                tint: .blue
            ),
            SummaryMetricItem(
                title: "Ready",
                value: "\(readyCount)",
                tint: .teal
            )
        ]

        if olderCount > 0 {
            metrics.append(
                SummaryMetricItem(
                    title: "Older",
                    value: "\(olderCount)",
                    tint: .orange
                )
            )
        } else if focusedProfile == nil {
            metrics.append(
                SummaryMetricItem(
                    title: "Servers",
                    value: "\(scopedServerCount)",
                    tint: .secondary
                )
            )
        }

        return metrics
    }

    private var summaryMetadataItems: [RemoteInlineMetadataItem] {
        var items = [RemoteInlineMetadataItem]()

        if !viewModel.cacheSummary.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "internaldrive",
                    text: viewModel.cacheSummary.summaryText,
                    tint: .secondary
                )
            )
        }

        if let focusedProfile {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "server.rack",
                    text: focusedProfile.name,
                    tint: .secondary
                )
            )
        } else if scopedServerCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "server.rack",
                    text: scopedServerCount == 1 ? "1 server" : "\(scopedServerCount) servers",
                    tint: .secondary
                )
            )
        }

        if !trimmedSearchText.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "magnifyingglass",
                    text: "Search: \(trimmedSearchText)",
                    tint: .pink
                )
            )
        }

        if filterMode != .all {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "line.3.horizontal.decrease.circle",
                    text: filterMode.title,
                    tint: .orange
                )
            )
        }

        items.append(
            RemoteInlineMetadataItem(
                systemImage: sortMode.systemImageName,
                text: "Sorted by \(sortMode.title)",
                tint: .teal
            )
        )

        return items
    }

    @ViewBuilder
    private func selectionMenuLabel(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: RemoteOfflineShelfSection) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.profile.name)
                    .font(.subheadline.weight(.semibold))

                RemoteInlineMetadataLine(
                    items: sectionHeaderMetadataItems(for: section),
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                )
            }

            Spacer(minLength: 10)

            Menu {
                Button(role: .destructive) {
                    pendingServerClearProfile = section.profile
                    pendingServerClearCount = viewModel.downloadedCopyCount(for: section.profile)
                } label: {
                    Label(
                        section.entries.count == 1 ? "Clear Downloaded Copy" : "Clear Downloaded Copies",
                        systemImage: "trash"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage \(section.profile.name)")
        }
        .textCase(nil)
    }

    private func sectionHeaderMetadataItems(
        for section: RemoteOfflineShelfSection
    ) -> [RemoteInlineMetadataItem] {
        var items = [RemoteInlineMetadataItem]()

        if section.readyCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "arrow.down.circle.fill",
                    text: section.readyCount == 1 ? "1 ready" : "\(section.readyCount) ready",
                    tint: .blue
                )
            )
        }

        if section.olderCount > 0 {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                    text: section.olderCount == 1 ? "1 older" : "\(section.olderCount) older",
                    tint: .orange
                )
            )
        }

        if items.isEmpty {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "arrow.down.circle",
                    text: section.entries.count == 1 ? "1 downloaded copy" : "\(section.entries.count) downloaded copies",
                    tint: .secondary
                )
            )
        }

        return items
    }

    private var summaryDescription: String {
        if !trimmedSearchText.isEmpty {
            return displayedEntries.count == 1
                ? "1 offline copy matches the current search."
                : "\(displayedEntries.count) offline copies match the current search."
        }

        switch filterMode {
        case .all:
            if let focusedProfile {
                return "Downloaded comics from \(focusedProfile.name) stay available on this device."
            }

            return "Downloaded comics stay available on this device across your configured servers."
        case .current:
            return "Showing offline copies that are ready and current on this device."
        case .stale:
            return "Showing older local copies that may need a refresh."
        }
    }

    private var scopedServerCount: Int {
        Set(scopedEntries.map(\.profile.id)).count
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

    @ViewBuilder
    private func offlineShelfItemActionMenuContent(
        for entry: RemoteOfflineComicEntry
    ) -> some View {
        Button {
            navigationRequest = .folder(
                entry.profile,
                entry.session.parentDirectoryPath
            )
        } label: {
            Label("Browse Source Folder", systemImage: "folder")
        }

        Button {
            Task<Void, Never> {
                await viewModel.refreshDownloadedCopy(for: entry)
            }
        } label: {
            Label("Refresh Downloaded Copy", systemImage: "arrow.clockwise.circle")
        }

        Button(role: .destructive) {
            pendingRemovalEntry = entry
        } label: {
            Label("Delete Downloaded Copy", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func offlineShelfItemSwipeActions(
        for entry: RemoteOfflineComicEntry
    ) -> some View {
        Button {
            Task<Void, Never> {
                await viewModel.refreshDownloadedCopy(for: entry)
            }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise.circle")
        }
        .tint(.blue)

        Button(role: .destructive) {
            pendingRemovalEntry = entry
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct RemoteOfflineShelfSection: Identifiable {
    let profile: RemoteServerProfile
    let entries: [RemoteOfflineComicEntry]

    var id: UUID {
        profile.id
    }

    var readyCount: Int {
        entries.filter { $0.availability.kind == .current }.count
    }

    var olderCount: Int {
        entries.filter { $0.availability.kind == .stale }.count
    }
}
