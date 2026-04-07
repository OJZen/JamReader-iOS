import Combine
import SwiftUI
import UIKit

private enum RemoteOfflineShelfLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let rowAccessoryReservedWidth: CGFloat = 36
}

private enum RemoteOfflineShelfSortMode: String, CaseIterable, Identifiable {
    case recent
    case title
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return "Recent"
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
            return "Current"
        case .stale:
            return "Older"
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

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await load()
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            try rebuildEntries(forceRefresh: forceRefresh)
            alert = nil
        } catch {
            entries = []
            cacheSummary = .empty
            alert = BrowseHomeAlert(
                title: "Offline Shelf Unavailable",
                message: error.userFacingMessage
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
            try rebuildEntries(forceRefresh: true)

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
            try rebuildEntries(forceRefresh: true)
            feedback = RemoteBrowserFeedbackState(
                title: "Downloaded Copy Removed",
                message: "\(entry.session.displayName) was removed from this device.",
                kind: .info,
                autoDismissAfter: 2.6
            )
        } catch {
            alert = BrowseHomeAlert(
                title: "Remove Downloaded Copy Failed",
                message: error.userFacingMessage
            )
        }
    }

    func clearDownloadedCopies(for profile: RemoteServerProfile, removedCount: Int) {
        feedback = nil

        do {
            try remoteServerBrowsingService.clearCachedComics(for: profile)
            try remoteReadingProgressStore.deleteSessions(for: profile)
            RemoteServerBrowserViewModel.clearRememberedPath(for: profile)
            try rebuildEntries(forceRefresh: true)
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
            try? rebuildEntries(forceRefresh: true)
            alert = BrowseHomeAlert(
                title: "Offline Shelf Action Failed",
                message: error.userFacingMessage
            )
        }
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: RemoteOfflineShelfViewModel
    @State private var searchText = ""
    @State private var sortMode: RemoteOfflineShelfSortMode = .recent
    @State private var filterMode: RemoteOfflineShelfFilter = .all
    @State private var navigationRequest: RemoteOfflineShelfNavigationRequest?
    @State private var feedbackDismissTask: Task<Void, Never>?
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
            if scopedEntries.isEmpty, !viewModel.isLoading {
                Section {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "No Downloads",
                        description: focusedProfile == nil
                            ? "Save comics for offline reading."
                            : "Save comics from this server."
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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                prepareHeroTransition(for: entry, fallbackFrame: .zero)
                                presentedEntry = entry
                            }
                            .insetCardListRow(horizontalInset: RemoteOfflineShelfLayoutMetrics.horizontalInset)
                            .overlay(alignment: .trailing) {
                                if showsPersistentItemActions {
                                    offlineShelfItemActionMenu(for: entry)
                                        .padding(.trailing, 8)
                                }
                            }
                            .contextMenu {
                                offlineShelfItemActionMenuContent(for: entry)
                            }
                        }
                    } header: {
                        sectionHeader(for: section)
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
                .accessibilityLabel("Options")
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search shelf"
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
            return "No Downloads"
        case .current:
            return "No Current Copies"
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
            return "No downloads on this device."
        case .current:
            return "No current local copies."
        case .stale:
            return "No older local copies."
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
                        section.entries.count == 1 ? "Clear Download" : "Clear Downloads",
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

    private func sectionHeaderDetailText(
        for section: RemoteOfflineShelfSection
    ) -> String {
        if section.readyCount > 0, section.olderCount > 0 {
            return "\(section.entries.count) downloads · \(section.readyCount) current · \(section.olderCount) older"
        }

        if section.readyCount > 0 {
            return "\(section.entries.count) downloads · \(section.readyCount) current"
        }

        if section.olderCount > 0 {
            return "\(section.entries.count) downloads · \(section.olderCount) older"
        }

        return section.entries.count == 1 ? "1 download" : "\(section.entries.count) downloads"
    }

    private var showsPersistentItemActions: Bool {
        horizontalSizeClass == .regular
    }

    private var itemAccessoryReservedWidth: CGFloat {
        showsPersistentItemActions ? RemoteOfflineShelfLayoutMetrics.rowAccessoryReservedWidth : 0
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
            title: "Delete this download?",
            message: "Deletes the downloaded copy of \"\(entry.session.displayName)\" only.",
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "Cancel", style: .cancel)
        )
        alertController.addAction(
            UIAlertAction(title: "Delete Copy", style: .destructive) { _ in
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
            UIAlertAction(title: "OK", style: .default) { _ in
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
