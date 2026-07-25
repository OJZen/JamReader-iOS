import Combine
import SwiftUI
import UIKit
import os

private enum RemoteOfflineShelfLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let rowAccessoryReservedWidth = AppLayout.persistentRowActionReservedWidth
    static let gridVerticalPadding: CGFloat = 6
}

private enum RemoteOfflineShelfSortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return String(localized: "Recent")
        case .title:
            return String(localized: "Title")
        case .server:
            return String(localized: "Server")
        }
    }

    var shortTitle: String {
        switch self {
        case .recent:
            return String(localized: "Recent")
        case .title:
            return String(localized: "Title")
        case .server:
            return String(localized: "Server")
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
            return String(localized: "All")
        case .current:
            return String(localized: "Latest")
        case .stale:
            return String(localized: "Older")
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

enum RemoteOfflineShelfLoadState: Equatable {
    case idle
    case loading
    case loaded
    case refreshing
    case failed(message: String)
}

@MainActor
final class RemoteOfflineShelfViewModel: ObservableObject {
    @Published private(set) var entries: [RemoteOfflineComicEntry] = []
    @Published private(set) var cacheSummary: RemoteComicCacheSummary = .empty
    @Published private(set) var loadState: RemoteOfflineShelfLoadState = .idle
    @Published var feedback: RemoteBrowserFeedbackState?
    @Published var alert: BrowseHomeAlert?

    private let remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore
    private let remoteServerBrowsingService: RemoteServerBrowsingService
    private let remoteReadingProgressStore: RemoteReadingProgressStore
    private let remoteOfflineCopyStore: RemoteOfflineCopyStore
    private let remoteBackgroundImportController: RemoteBackgroundImportController
    private var hasAttemptedInitialLoad = false
    private let logger = AppLog.remoteCache

    init(dependencies: AppDependencies) {
        self.remoteOfflineLibrarySnapshotStore = dependencies.remoteOfflineLibrarySnapshotStore
        self.remoteServerBrowsingService = dependencies.remoteServerBrowsingService
        self.remoteReadingProgressStore = dependencies.remoteReadingProgressStore
        self.remoteOfflineCopyStore = dependencies.remoteOfflineCopyStore
        self.remoteBackgroundImportController = dependencies.remoteBackgroundImportController
    }

    init(
        remoteOfflineLibrarySnapshotStore: RemoteOfflineLibrarySnapshotStore,
        remoteServerBrowsingService: RemoteServerBrowsingService,
        remoteReadingProgressStore: RemoteReadingProgressStore,
        remoteOfflineCopyStore: RemoteOfflineCopyStore,
        remoteBackgroundImportController: RemoteBackgroundImportController
    ) {
        self.remoteOfflineLibrarySnapshotStore = remoteOfflineLibrarySnapshotStore
        self.remoteServerBrowsingService = remoteServerBrowsingService
        self.remoteReadingProgressStore = remoteReadingProgressStore
        self.remoteOfflineCopyStore = remoteOfflineCopyStore
        self.remoteBackgroundImportController = remoteBackgroundImportController
    }

    var isLoading: Bool {
        switch loadState {
        case .loading, .refreshing:
            return true
        case .idle, .loaded, .failed:
            return false
        }
    }

    var isInitialLoading: Bool {
        entries.isEmpty && (
            loadState == .idle
                || loadState == .loading
                || loadState == .refreshing
        )
    }

    var loadFailureMessage: String? {
        guard case .failed(let message) = loadState else {
            return nil
        }
        return message
    }

    func loadIfNeeded() async {
        guard !hasAttemptedInitialLoad else {
            return
        }

        hasAttemptedInitialLoad = true
        await load()
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else {
            return
        }

        loadState = entries.isEmpty ? .loading : .refreshing
        hasAttemptedInitialLoad = true

        logger.info("Remote offline shelf load requested forceRefresh=\(forceRefresh)")
        do {
            try rebuildEntries(forceRefresh: forceRefresh)
            loadState = .loaded
            logger.info(
                "Remote offline shelf load completed entries=\(self.entries.count) cacheFiles=\(self.cacheSummary.fileCount) cacheBytes=\(self.cacheSummary.totalBytes)"
            )
            alert = nil
        } catch {
            logger.error(
                "Remote offline shelf load failed forceRefresh=\(forceRefresh) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            loadState = .failed(message: error.userFacingMessage)
            alert = BrowseHomeAlert(
                title: String(localized: "Offline Shelf Unavailable"),
                message: error.userFacingMessage
            )
        }
    }

    func refreshDownloadedCopy(for entry: RemoteOfflineComicEntry) async {
        feedback = nil
        guard beginStorageMaintenance() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        let pathForLog = AppLogSanitizer.path(entry.session.path)
        logger.notice(
            "Remote offline copy refresh requested serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public)"
        )

        await activeOperation {
            let reference = entry.session.resolvedComicFileReference(for: entry.profile)
            let result = try await remoteServerBrowsingService.downloadComicFile(
                for: entry.profile,
                reference: reference,
                forceRefresh: true,
                trimCacheAfterDownload: false,
                stageCacheReplacementForRollback: true
            )
            let persistenceCandidate = RemoteOfflineCopyPersistenceCandidate(
                reference: reference,
                result: result
            )
            try RemoteOfflineCopyPersistenceCoordinator.persist(
                candidates: [persistenceCandidate],
                persistRecords: {
                    try remoteOfflineCopyStore.recordDownloadedCopy(for: reference)
                },
                commitDownloadedCache: { candidate in
                    try remoteServerBrowsingService.commitDownloadedComicCache(
                        for: candidate.reference,
                        result: candidate.result
                    )
                },
                rollbackDownloadedCache: { candidate in
                    try remoteServerBrowsingService.rollbackDownloadedComicCache(
                        for: candidate.reference,
                        result: candidate.result
                    )
                },
                rollbackFailureHandler: { [logger = self.logger] reference, error in
                    logger.warning(
                        "Remote offline refresh rollback failed serverID=\(reference.serverID.uuidString, privacy: .public) path=\(AppLogSanitizer.path(reference.path), privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                    )
                }
            )
            try rebuildEntries(forceRefresh: true)
            logger.info(
                "Remote offline copy refresh completed serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public) source=\(Self.downloadSourceLogValue(result.source), privacy: .public)"
            )

            feedback = RemoteBrowserFeedbackState(
                title: String(localized: "Downloaded Copy Updated"),
                message: refreshFeedbackMessage(for: entry, result: result),
                kind: .success,
                autoDismissAfter: 3.2
            )
        }
    }

    func removeDownloadedCopy(for entry: RemoteOfflineComicEntry) {
        feedback = nil
        guard beginStorageMaintenance() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        let pathForLog = AppLogSanitizer.path(entry.session.path)
        logger.notice(
            "Remote offline copy remove requested serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public)"
        )

        remoteOfflineLibrarySnapshotStore.invalidate()
        do {
            let reference = entry.session.resolvedComicFileReference(for: entry.profile)
            try remoteServerBrowsingService.clearCachedComic(for: reference)
            try remoteOfflineCopyStore.removeCopy(for: reference)
            try rebuildEntries(forceRefresh: true)
            logger.info(
                "Remote offline copy remove completed serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public) remaining=\(self.entries.count)"
            )
            feedback = RemoteBrowserFeedbackState(
                title: String(localized: "Downloaded Copy Removed"),
                message: String(localized: "\(entry.session.displayName) was removed from this device."),
                kind: .info,
                autoDismissAfter: 2.6
            )
        } catch {
            logger.error(
                "Remote offline copy remove failed serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            do {
                try rebuildEntries(forceRefresh: true)
            } catch {
                logger.warning(
                    "Remote offline shelf rebuild after remove failure failed serverID=\(entry.profile.id.uuidString, privacy: .public) path=\(pathForLog, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
            alert = BrowseHomeAlert(
                title: String(localized: "Remove Downloaded Copy Failed"),
                message: error.userFacingMessage
            )
        }
    }

    func clearDownloadedCopies(for profile: RemoteServerProfile, removedCount: Int) {
        feedback = nil
        guard beginStorageMaintenance() else {
            return
        }
        defer {
            remoteBackgroundImportController.endExclusiveStorageMaintenance()
        }

        logger.notice(
            "Remote offline copies clear requested serverID=\(profile.id.uuidString, privacy: .public) count=\(removedCount)"
        )

        remoteOfflineLibrarySnapshotStore.invalidate()
        do {
            try remoteServerBrowsingService.clearCachedComics(for: profile)
            try remoteOfflineCopyStore.removeCopies(for: profile)
            try remoteReadingProgressStore.deleteSessions(for: profile)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            try rebuildEntries(forceRefresh: true)
            logger.info(
                "Remote offline copies clear completed serverID=\(profile.id.uuidString, privacy: .public) requestedCount=\(removedCount) remaining=\(self.entries.count)"
            )
            feedback = RemoteBrowserFeedbackState(
                title: String(localized: "Downloaded Copies Removed"),
                message: removedCount == 1
                    ? String(localized: "Removed 1 downloaded copy from \(profile.name) and cleared its browsing history.")
                    : String(localized: "Removed \(removedCount) downloaded copies from \(profile.name) and cleared its browsing history."),
                kind: .info,
                autoDismissAfter: 3.0
            )
        } catch {
            logger.error(
                "Remote offline copies clear failed serverID=\(profile.id.uuidString, privacy: .public) requestedCount=\(removedCount) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            do {
                try rebuildEntries(forceRefresh: true)
            } catch {
                logger.warning(
                    "Remote offline shelf rebuild after clear failure failed serverID=\(profile.id.uuidString, privacy: .public) error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
            alert = BrowseHomeAlert(
                title: String(localized: "Clear Downloaded Copies Failed"),
                message: error.userFacingMessage
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
            logger.error(
                "Remote offline shelf action failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
            )
            do {
                try rebuildEntries(forceRefresh: true)
            } catch {
                logger.warning(
                    "Remote offline shelf rebuild after action failure failed error=\(AppLogSanitizer.errorDescription(error), privacy: .public)"
                )
            }
            alert = BrowseHomeAlert(
                title: String(localized: "Offline Shelf Action Failed"),
                message: error.userFacingMessage
            )
        }
    }

    private func beginStorageMaintenance() -> Bool {
        guard remoteBackgroundImportController.beginExclusiveStorageMaintenance() else {
            alert = BrowseHomeAlert(
                title: String(localized: "Remote Task in Progress"),
                message: String(localized: "Wait for the current remote task to finish.")
            )
            return false
        }

        return true
    }

    private func rebuildEntries(forceRefresh: Bool = false) throws {
        if forceRefresh {
            remoteOfflineLibrarySnapshotStore.invalidate()
        }

        let snapshot = try remoteOfflineLibrarySnapshotStore.loadSnapshot(forceRefresh: forceRefresh)
        entries = snapshot.offlineEntries
        cacheSummary = snapshot.cacheSummary
    }

    private func refreshFeedbackMessage(
        for entry: RemoteOfflineComicEntry,
        result: RemoteComicDownloadResult
    ) -> String {
        switch result.source {
        case .downloaded:
            return String(localized: "Downloaded the latest copy of \(entry.session.displayName) to this device.")
        case .cachedCurrent:
            return String(localized: "\(entry.session.displayName) is already current on this device.")
        case .cachedFallback(let message):
            return message
        }
    }

    nonisolated private static func downloadSourceLogValue(_ source: RemoteComicDownloadResult.Source) -> String {
        switch source {
        case .downloaded:
            return "downloaded"
        case .cachedCurrent:
            return "cachedCurrent"
        case .cachedFallback:
            return "cachedFallback"
        }
    }
}

struct RemoteOfflineShelfView: View {
    let dependencies: AppDependencies
    let focusedProfile: RemoteServerProfile?

    @Environment(\.appNavigator) private var appNavigator
    @Environment(\.appPresenter) private var appPresenter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: RemoteOfflineShelfViewModel
    @State private var searchText = ""
    @State private var sortMode: RemoteOfflineShelfSortMode = .recent
    @State private var filterMode: RemoteOfflineShelfFilter = .all
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var pendingServerClearProfile: RemoteServerProfile?
    @State private var pendingServerClearCount = 0
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?
    @State private var containerWidth: CGFloat = 0

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
        GeometryReader { geometry in
            content
                .onAppear {
                    updateContainerWidth(geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    updateContainerWidth(newWidth)
                }
        }
        .background(background)
        .background(readerPresenter)
        .navigationTitle(navigationTitleText)
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
                .accessibilityLabel("Options")
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: searchPrompt
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
            await viewModel.load(forceRefresh: true)
        }
        .onChange(of: viewModel.feedback?.id) { _, _ in
            scheduleFeedbackDismissalIfNeeded()
        }
        .onChange(of: viewModel.alert?.id) { _, _ in
            guard let alert = viewModel.alert else {
                return
            }

            presentMessageAlert(alert)
        }
        .onDisappear {
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
        }
        .confirmationDialog(
            "Clear downloads for this server?",
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
                Button("Clear Downloads", role: .destructive) {
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
                Text("Deletes \(pendingServerClearCount) downloads from \(profile.name) only.")
            }
        }
    }

    private func updateContainerWidth(_ newWidth: CGFloat) {
        let normalizedWidth = max(newWidth, 0)
        guard Int(containerWidth.rounded(.toNearestOrAwayFromZero))
            != Int(normalizedWidth.rounded(.toNearestOrAwayFromZero))
        else {
            return
        }

        containerWidth = normalizedWidth
    }

    @ViewBuilder
    private var content: some View {
        if adaptiveListColumnCount > 1 {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if viewModel.isInitialLoading {
                        loadingCard
                    } else if scopedEntries.isEmpty,
                              let failureMessage = viewModel.loadFailureMessage {
                        loadFailureCard(message: failureMessage)
                    } else if scopedEntries.isEmpty {
                        emptyCard(
                            systemImage: "arrow.down.circle",
                            title: String(localized: "No Downloads"),
                            description: focusedProfile == nil
                                ? String(localized: "Save comics for offline reading.")
                                : String(localized: "Save comics from this server.")
                        )
                    } else if displayedEntries.isEmpty {
                        emptyCard(
                            systemImage: "magnifyingglass",
                            title: emptyResultsTitle,
                            description: emptyResultsDescription
                        )
                    } else {
                        ForEach(displayedSections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(for: section)

                                LazyVGrid(
                                    columns: offlineShelfGridColumns,
                                    alignment: .leading,
                                    spacing: adaptiveListColumnSpacing
                                ) {
                                    ForEach(section.entries) { entry in
                                        offlineShelfEntryRow(for: entry)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            List {
                if viewModel.isInitialLoading {
                    Section {
                        ProgressView("Loading Downloads")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                            .accessibilityIdentifier("remoteOfflineShelf.loading")
                    }
                } else if scopedEntries.isEmpty,
                          let failureMessage = viewModel.loadFailureMessage {
                    Section {
                        loadFailureContent(message: failureMessage)
                            .padding(.vertical, 24)
                    }
                } else if scopedEntries.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "arrow.down.circle",
                            title: String(localized: "No Downloads"),
                            description: focusedProfile == nil
                                ? String(localized: "Save comics for offline reading.")
                                : String(localized: "Save comics from this server.")
                        )
                        .padding(.vertical, 28)
                    }
                } else if displayedEntries.isEmpty {
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
                                offlineShelfEntryRow(for: entry)
                                    .insetCardListRow(
                                        horizontalInset: RemoteOfflineShelfLayoutMetrics.horizontalInset,
                                        top: RemoteOfflineShelfLayoutMetrics.gridVerticalPadding,
                                        bottom: RemoteOfflineShelfLayoutMetrics.gridVerticalPadding
                                    )
                            }
                        } header: {
                            sectionHeader(for: section)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var readerPresenter: some View {
        EmptyView()
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

    private func presentOfflineEntry(_ entry: RemoteOfflineComicEntry) {
        appPresenter?.presentReader(
            .remote(
                RemoteReaderPresentation(
                    profile: entry.profile,
                    item: entry.session.directoryItem,
                    openMode: .preferLocalCache,
                    referenceOverride: entry.session.resolvedComicFileReference(for: entry.profile),
                    sourceFrame: heroSourceFrame,
                    previewImage: heroPreviewImage,
                    onDismiss: {
                        heroSourceFrame = .zero
                        heroPreviewImage = nil
                    }
                )
            )
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

    private var navigationTitleText: String {
        if let focusedProfile {
            return String(localized: "\(focusedProfile.displayTitle) Downloads")
        }

        return String(localized: "Offline Shelf")
    }

    private var searchPrompt: String {
        if focusedProfile != nil {
            return String(localized: "Search this server's downloads")
        }

        return String(localized: "Search shelf")
    }

    private var scopedEntries: [RemoteOfflineComicEntry] {
        if let focusedProfile {
            return viewModel.entries.filter { $0.profile.id == focusedProfile.id }
        }

        return viewModel.entries
    }

    private var emptyResultsTitle: String {
        if !trimmedSearchText.isEmpty {
            return String(localized: "No Matches")
        }

        switch filterMode {
        case .all:
            return String(localized: "No Downloads")
        case .current:
            return String(localized: "No Current Copies")
        case .stale:
            return String(localized: "No Older Copies")
        }
    }

    private var emptyResultsDescription: String {
        if !trimmedSearchText.isEmpty {
            if let focusedProfile {
                return String(localized: "No matches for \"\(trimmedSearchText)\" in \(focusedProfile.displayTitle) downloads.")
            }

            return String(localized: "No matches for \"\(trimmedSearchText)\".")
        }

        switch filterMode {
        case .all:
            if let focusedProfile {
                return String(localized: "No downloads from \(focusedProfile.displayTitle) on this device.")
            }
            return String(localized: "No downloads on this device.")
        case .current:
            if let focusedProfile {
                return String(localized: "No current local copies from \(focusedProfile.displayTitle).")
            }
            return String(localized: "No current local copies.")
        case .stale:
            if let focusedProfile {
                return String(localized: "No older local copies from \(focusedProfile.displayTitle).")
            }
            return String(localized: "No older local copies.")
        }
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

    private func emptyCard(
        systemImage: String,
        title: String,
        description: String
    ) -> some View {
        InsetCard(
            cornerRadius: 20,
            contentPadding: 20,
            backgroundColor: Color(.secondarySystemBackground)
        ) {
            EmptyStateView(
                systemImage: systemImage,
                title: title,
                description: description
            )
            .padding(.vertical, 12)
        }
    }

    private var loadingCard: some View {
        InsetCard(
            cornerRadius: 20,
            contentPadding: 20,
            backgroundColor: Color(.secondarySystemBackground)
        ) {
            ProgressView("Loading Downloads")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .accessibilityIdentifier("remoteOfflineShelf.loading")
        }
    }

    private func loadFailureCard(message: String) -> some View {
        InsetCard(
            cornerRadius: 20,
            contentPadding: 20,
            backgroundColor: Color(.secondarySystemBackground)
        ) {
            loadFailureContent(message: message)
                .padding(.vertical, 12)
        }
    }

    private func loadFailureContent(message: String) -> some View {
        VStack(spacing: 12) {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: String(localized: "Downloads Unavailable"),
                description: message
            )

            Button("Try Again") {
                Task {
                    await viewModel.load(forceRefresh: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("remoteOfflineShelf.retry")
        }
    }

    @ViewBuilder
    private func sectionHeader(for section: RemoteOfflineShelfSection) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.profile.name)
                    .font(.subheadline.weight(.semibold))

                Text(sectionHeaderDetailText(for: section))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Menu {
                Button(role: .destructive) {
                    pendingServerClearProfile = section.profile
                    pendingServerClearCount = viewModel.downloadedCopyCount(for: section.profile)
                } label: {
                    Label(
                        section.entries.count == 1
                            ? String(localized: "Clear Download")
                            : String(localized: "Clear Downloads"),
                        systemImage: "trash"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage \(section.profile.name)")
        }
        .textCase(nil)
    }

    private func sectionHeaderDetailText(
        for section: RemoteOfflineShelfSection
    ) -> String {
        if section.readyCount > 0, section.olderCount > 0 {
            return String(localized: "\(section.entries.count) downloads · \(section.readyCount) current · \(section.olderCount) older")
        }

        if section.readyCount > 0 {
            return String(localized: "\(section.entries.count) downloads · \(section.readyCount) current")
        }

        if section.olderCount > 0 {
            return String(localized: "\(section.entries.count) downloads · \(section.olderCount) older")
        }

        return section.entries.count == 1
            ? String(localized: "1 download")
            : String(localized: "\(section.entries.count) downloads")
    }

    private var showsPersistentItemActions: Bool {
        adaptiveListColumnCount > 1
    }

    private var adaptiveListColumnCount: Int {
        AppLayout.adaptiveListColumnCount(
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: containerWidth
        )
    }

    private var adaptiveListColumnSpacing: CGFloat {
        AppLayout.adaptiveListColumnSpacing(for: adaptiveListColumnCount)
    }

    private var offlineShelfGridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: adaptiveListColumnSpacing, alignment: .top),
            count: adaptiveListColumnCount
        )
    }

    private var itemAccessoryReservedWidth: CGFloat {
        showsPersistentItemActions ? RemoteOfflineShelfLayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var background: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func offlineShelfEntryRow(
        for entry: RemoteOfflineComicEntry
    ) -> some View {
        let row = HeroTapButton { frame in
            prepareHeroTransition(for: entry, fallbackFrame: frame)
            presentOfflineEntry(entry)
        } label: {
            RemoteInsetListRowCard(contentPadding: 12) {
                RemoteOfflineComicCard(
                    session: entry.session,
                    profile: entry.profile,
                    availability: entry.availability,
                    browsingService: dependencies.remoteServerBrowsingService,
                    heroSourceID: entry.session.directoryItem.id,
                    showsNavigationIndicator: false,
                    showsServerName: false,
                    trailingAccessoryReservedWidth: itemAccessoryReservedWidth
                )
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if showsPersistentItemActions {
                offlineShelfItemActionMenu(for: entry)
                    .padding(.trailing, 8)
            }
        }

        if adaptiveListColumnCount == 1 {
            row.contextMenu {
                offlineShelfItemActionMenuContent(for: entry)
            }
        } else {
            row
        }
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
            appNavigator?.navigate(
                .browse(
                    .serverBrowser(
                        entry.profile.id,
                        path: entry.session.parentDirectoryPath
                    )
                )
            )
        } label: {
            Label("Browse Folder", systemImage: "folder")
        }

        Button {
            Task<Void, Never> {
                await viewModel.refreshDownloadedCopy(for: entry)
            }
        } label: {
            Label("Refresh Copy", systemImage: "arrow.clockwise.circle")
        }

        Button(role: .destructive) {
            presentRemovalConfirmation(for: entry)
        } label: {
            Label("Delete Copy", systemImage: "trash")
        }
    }

    private func offlineShelfItemActionMenu(
        for entry: RemoteOfflineComicEntry
    ) -> some View {
        Menu {
            offlineShelfItemActionMenuContent(for: entry)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(entry.session.displayName)")
    }

    private func presentRemovalConfirmation(for entry: RemoteOfflineComicEntry) {
        presentDeleteAlert(for: entry)
    }

    private func presentDeleteAlert(for entry: RemoteOfflineComicEntry) {
        let viewModel = self.viewModel
        let alertController = UIAlertController(
            title: String(localized: "Delete this download?"),
            message: String(localized: "Deletes the downloaded copy of \"\(entry.session.displayName)\" only."),
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: String(localized: "Cancel"), style: .cancel)
        )
        alertController.addAction(
            UIAlertAction(title: String(localized: "Delete Copy"), style: .destructive) { _ in
                viewModel.removeDownloadedCopy(for: entry)
            }
        )
        presentAlertController(alertController)
    }

    private func presentMessageAlert(_ alert: BrowseHomeAlert) {
        let viewModel = self.viewModel
        let alertController = UIAlertController(
            title: alert.title,
            message: alert.message,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                viewModel.alert = nil
            }
        )
        presentAlertController(alertController)
    }

    private func presentAlertController(_ alertController: UIAlertController) {
        guard let presenter = topAlertPresentationController() else {
            return
        }

        if let existingAlert = presenter as? UIAlertController,
           let host = existingAlert.presentingViewController {
            existingAlert.dismiss(animated: false) {
                host.present(alertController, animated: true)
            }
            return
        }

        presenter.present(alertController, animated: true)
    }

    private func topAlertPresentationController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: {
                $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
            })
        let keyWindow = windowScene?.windows.first(where: \.isKeyWindow) ?? windowScene?.windows.first
        return deepestPresentedViewController(from: keyWindow?.rootViewController)
    }

    private func deepestPresentedViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return deepestPresentedViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = controller as? UITabBarController {
            return deepestPresentedViewController(from: tabBarController.selectedViewController)
        }

        if let splitViewController = controller as? UISplitViewController,
           let lastController = splitViewController.viewControllers.last {
            return deepestPresentedViewController(from: lastController)
        }

        if let presentedViewController = controller?.presentedViewController {
            return deepestPresentedViewController(from: presentedViewController)
        }

        return controller
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
