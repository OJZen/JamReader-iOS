import SwiftUI
import UIKit

private enum RemoteServerDetailLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let rowAccessoryReservedWidth: CGFloat = 36
    static let persistentActionMinWidth: CGFloat = 560
}

struct RemoteServerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies
    private let sourceProfile: RemoteServerProfile
    // Called instead of local sheet when parent owns the editor (split-view mode).
    var onRequestEdit: ((RemoteServerEditorDraft) -> Void)?

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var profile: RemoteServerProfile
    @State private var recentSessions: [RemoteComicReadingSession] = []
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var navigationRequest: RemoteServerDetailNavigationRequest?
    @State private var presentedRecentSession: RemoteComicReadingSession?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?
    @State private var containerWidth: CGFloat = 0

    init(
        profile: RemoteServerProfile,
        dependencies: AppDependencies,
        onRequestEdit: ((RemoteServerEditorDraft) -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.sourceProfile = profile
        self.onRequestEdit = onRequestEdit
        _profile = State(initialValue: profile)
        _viewModel = StateObject(
            wrappedValue: RemoteServerListViewModel(
                profileStore: dependencies.remoteServerProfileStore,
                folderShortcutStore: dependencies.remoteFolderShortcutStore,
                credentialStore: dependencies.remoteServerCredentialStore,
                browsingService: dependencies.remoteServerBrowsingService,
                readingProgressStore: dependencies.remoteReadingProgressStore
            )
        )
    }

    var body: some View {
        List {
            connectionSection
            quickAccessSection
            recentComicsSection
        }
        .navigationTitle(profile.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .readContainerWidth(into: $containerWidth)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    remoteServerActionMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Server Actions")
            }
        }
        .task {
            viewModel.loadIfNeeded()
            refreshDetailState()
        }
        .onAppear {
            refreshDetailState(forceReload: true)
        }
        .onChange(of: sourceProfile) { _, updated in
            // When the parent (split-view sidebar) passes an updated profile
            // after a save, sync state and reload so the detail stays current.
            profile = updated
            refreshDetailState()
        }
        .refreshable {
            refreshDetailState(forceReload: true)
        }
        // Only present the editor sheet locally in compact (iPhone) mode.
        // In split-view the parent's sidebar sheet owns the presentation so
        // that exactly ONE sheet is active in the window at a time.
        .sheet(item: $editorDraft) { draft in
            remoteServerEditor(for: draft)
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .navigationDestination(item: $navigationRequest) { request in
            switch request {
            case .browser(let profile):
                RemoteServerBrowserView(
                    profile: profile,
                    currentPath: RemoteServerBrowserViewModel.lastBrowsedPath(for: profile),
                    dependencies: dependencies
                )
            case .comic(let item):
                RemoteComicLoadingView(
                    profile: profile,
                    item: item,
                    dependencies: dependencies
                )
            case .savedFolders(let profile):
                SavedRemoteFoldersView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            case .offlineShelf(let profile):
                RemoteOfflineShelfView(
                    dependencies: dependencies,
                    focusedProfile: profile
                )
            }
        }
        .background(readerPresenter)
    }

    @ViewBuilder
    private var readerPresenter: some View {
        HeroReaderPresenter(
            item: $presentedRecentSession,
            sourceFrame: heroSourceFrame,
            previewImage: heroPreviewImage,
            onDismiss: {
                heroSourceFrame = .zero
                heroPreviewImage = nil
            }
        ) { session in
            RemoteComicLoadingView(
                profile: profile,
                item: session.directoryItem,
                dependencies: dependencies,
                referenceOverride: session.resolvedComicFileReference(for: profile)
            )
        }
    }

    private func remoteServerEditor(
        for draft: RemoteServerEditorDraft
    ) -> some View {
        RemoteServerEditorSheet(draft: draft) { updatedDraft in
            let alertState = viewModel.save(draft: updatedDraft)
            if alertState == nil {
                editorDraft = nil
                refreshDetailState(forceReload: true)
            }
            return alertState
        }
        .id(draft.id)
    }

    private var connectionSection: some View {
        Section("Server") {
            LabeledContent("Type") {
                Text(profile.providerDisplayTitle)
                    .foregroundStyle(profile.providerKind.tintColor)
            }

            LabeledContent("Server") {
                Text(profile.endpointDisplaySummary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent("Path") {
                Text(profile.shareDisplaySummary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }

            if !profile.username.isEmpty, profile.authenticationMode.requiresUsername {
                LabeledContent("Username") {
                    Text(profile.username)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var quickAccessSection: some View {
        Section("Shortcuts") {
            ForEach(quickAccessItems) { item in
                Button {
                    navigationRequest = item.navigationRequest
                } label: {
                    RemoteServerDetailShortcutRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentComicsSection: some View {
        Section("Recent") {
            if recentSessions.isEmpty {
                ContentUnavailableView(
                    "No Recent Comics",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Open a comic on this server to keep it here.")
                )
                .padding(.vertical, 24)
            } else {
                ForEach(recentSessions) { session in
                    HeroTapButton { frame in
                        prepareHeroTransition(for: session, fallbackFrame: frame)
                        presentedRecentSession = session
                    } label: {
                        RemoteInsetListRowCard {
                            RemoteOfflineComicCard(
                                session: session,
                                profile: profile,
                                availability: dependencies.remoteServerBrowsingService.cachedAvailability(
                                    for: session.resolvedComicFileReference(for: profile)
                                ),
                                browsingService: dependencies.remoteServerBrowsingService,
                                heroSourceID: session.directoryItem.id,
                                showsNavigationIndicator: false,
                                showsServerName: false,
                                trailingAccessoryReservedWidth: recentSessionAccessoryReservedWidth
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .insetCardListRow(horizontalInset: RemoteServerDetailLayoutMetrics.horizontalInset)
                    .overlay(alignment: .trailing) {
                        if showsPersistentRecentSessionActions {
                            recentSessionActionMenu(for: session)
                                .padding(.trailing, 8)
                        }
                    }
                    .contextMenu {
                        recentSessionActionMenuContent(for: session)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        recentSessionSwipeActions(for: session)
                    }
                }
            }
        }
    }

    @MainActor
    private func prepareHeroTransition(for session: RemoteComicReadingSession, fallbackFrame: CGRect) {
        let item = session.directoryItem
        let registeredFrame = HeroSourceRegistry.shared.frame(for: item.id)
        heroSourceFrame = registeredFrame == .zero ? fallbackFrame : registeredFrame
        heroPreviewImage = RemoteComicThumbnailPipeline.shared.cachedTransitionImage(
            for: item,
            browsingService: dependencies.remoteServerBrowsingService
        )
    }

    private var recentHistoryCount: Int {
        recentSessions.count
    }

    private var showsPersistentRecentSessionActions: Bool {
        horizontalSizeClass == .regular
            && containerWidth >= RemoteServerDetailLayoutMetrics.persistentActionMinWidth
    }

    private var recentSessionAccessoryReservedWidth: CGFloat {
        showsPersistentRecentSessionActions ? RemoteServerDetailLayoutMetrics.rowAccessoryReservedWidth : 0
    }

    private var savedFolderCount: Int {
        viewModel.shortcutCount(for: profile)
    }

    private var offlineCopyCount: Int {
        viewModel.cacheSummary(for: profile).fileCount
    }

    private var browserEntryRawPath: String {
        RemoteServerBrowserViewModel.lastBrowsedPath(for: profile)
    }

    private var browserEntryIsRoot: Bool {
        browserEntryRawPath == profile.normalizedBaseDirectoryPath
    }

    private var browserEntryTitle: String {
        browserEntryIsRoot ? "Browse" : "Continue"
    }

    private var browserEntryDisplayText: String {
        browserEntryRawPath.isEmpty ? "/" : browserEntryRawPath
    }

    private var quickAccessItems: [RemoteServerDetailShortcutItem] {
        var items = [
            RemoteServerDetailShortcutItem(
                id: "browse",
                title: browserEntryTitle,
                subtitle: browserEntryDisplayText,
                systemImage: browserEntryIsRoot ? "square.grid.2x2.fill" : "folder.fill",
                tint: browserEntryIsRoot ? .teal : .blue,
                navigationRequest: .browser(profile)
            )
        ]

        if savedFolderCount > 0 {
            items.append(
                RemoteServerDetailShortcutItem(
                    id: "saved-folders",
                    title: "Saved Folders",
                    subtitle: savedFolderCount == 1 ? "1 saved" : "\(savedFolderCount) saved",
                    systemImage: "star.fill",
                    tint: .teal,
                    navigationRequest: .savedFolders(profile)
                )
            )
        }

        if offlineCopyCount > 0 {
            items.append(
                RemoteServerDetailShortcutItem(
                    id: "offline-shelf",
                    title: "Offline Shelf",
                    subtitle: offlineCopyCount == 1 ? "1 downloaded" : "\(offlineCopyCount) downloaded",
                    systemImage: "arrow.down.circle.fill",
                    tint: .green,
                    navigationRequest: .offlineShelf(profile)
                )
            )
        }

        return items
    }

    @ViewBuilder
    private var remoteServerActionMenuContent: some View {
        Button {
            let draft = viewModel.makeEditDraft(for: profile)
            if let onRequestEdit {
                onRequestEdit(draft)
            } else {
                editorDraft = draft
            }
        } label: {
            Label("Edit Server", systemImage: "square.and.pencil")
        }

        if savedFolderCount > 0 {
            Button {
                navigationRequest = .savedFolders(profile)
            } label: {
                Label(
                    savedFolderCount == 1 ? "Saved Folder" : "Saved Folders",
                    systemImage: "star"
                )
            }
        }

        if offlineCopyCount > 0 {
            Button {
                navigationRequest = .offlineShelf(profile)
            } label: {
                Label(
                    offlineCopyCount == 1 ? "Offline Copy" : "Offline Shelf",
                    systemImage: "arrow.down.circle"
                )
            }
        }

        if recentHistoryCount > 0 {
            Button(role: .destructive) {
                viewModel.clearRecentHistory(for: profile)
                refreshDetailState(forceReload: true)
            } label: {
                Label("Clear History", systemImage: "clock.arrow.circlepath")
            }
        }

        if !viewModel.cacheSummary(for: profile).isEmpty {
            Button(role: .destructive) {
                viewModel.clearCache(for: profile)
                refreshDetailState(forceReload: true)
            } label: {
                Label("Clear Downloads", systemImage: "trash")
            }
        }

        Button(role: .destructive) {
            viewModel.delete(profile)
            dismiss()
        } label: {
            Label("Delete Server", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func recentSessionActionMenuContent(
        for session: RemoteComicReadingSession
    ) -> some View {
        Button(role: .destructive) {
            deleteRecentSession(session)
        } label: {
            Label("Delete History Entry", systemImage: "trash")
        }
    }

    private func recentSessionActionMenu(
        for session: RemoteComicReadingSession
    ) -> some View {
        Menu {
            recentSessionActionMenuContent(for: session)
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(session.displayName)")
    }

    @ViewBuilder
    private func recentSessionSwipeActions(
        for session: RemoteComicReadingSession
    ) -> some View {
        Button(role: .destructive) {
            deleteRecentSession(session)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteRecentSession(_ session: RemoteComicReadingSession) {
        viewModel.deleteRecentSession(session)
        refreshDetailState(forceReload: true)
    }

    private func refreshDetailState(forceReload: Bool = false) {
        if forceReload {
            viewModel.load()
        }

        if let updatedProfile = viewModel.profile(withID: profile.id) {
            profile = updatedProfile
        }

        recentSessions = viewModel.recentSessions(for: profile)
    }
}

private enum RemoteServerDetailNavigationRequest: Identifiable, Hashable {
    case browser(RemoteServerProfile)
    case comic(RemoteDirectoryItem)
    case savedFolders(RemoteServerProfile)
    case offlineShelf(RemoteServerProfile)

    var id: String {
        switch self {
        case .browser(let profile):
            return "browser:\(profile.id.uuidString)"
        case .comic(let item):
            return "comic:\(item.id)"
        case .savedFolders(let profile):
            return "saved:\(profile.id.uuidString)"
        case .offlineShelf(let profile):
            return "offline:\(profile.id.uuidString)"
        }
    }
}

private struct RemoteServerDetailShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let navigationRequest: RemoteServerDetailNavigationRequest
}

private struct RemoteServerDetailShortcutRow: View {
    let item: RemoteServerDetailShortcutItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: item.systemImage,
                tint: item.tint
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)

                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.right")
                .font(AppFont.caption2(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}
