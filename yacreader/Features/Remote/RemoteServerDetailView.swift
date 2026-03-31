import SwiftUI
import UIKit

private enum RemoteServerDetailLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let rowAccessoryReservedWidth: CGFloat = 36
}

struct RemoteServerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var profile: RemoteServerProfile
    @State private var recentSessions: [RemoteComicReadingSession] = []
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var navigationRequest: RemoteServerDetailNavigationRequest?
    @State private var presentedRecentSession: RemoteComicReadingSession?
    @State private var heroSourceFrame: CGRect = .zero
    @State private var heroPreviewImage: UIImage?

    init(profile: RemoteServerProfile, dependencies: AppDependencies) {
        self.dependencies = dependencies
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
            summarySection
            quickAccessSection
            recentComicsSection
        }
        .navigationTitle(profile.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
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
        .refreshable {
            refreshDetailState(forceReload: true)
        }
        .sheet(isPresented: serverEditorPresented) {
            if let draft = editorDraft {
                remoteServerEditor(for: draft)
            }
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
                dependencies: dependencies
            )
        }
    }

    private var summarySection: some View {
        Section {
            serverSummaryCard
                .insetCardListRow(
                    horizontalInset: RemoteServerDetailLayoutMetrics.horizontalInset,
                    top: 14,
                    bottom: 10
                )
        }
    }

    private var serverEditorPresented: Binding<Bool> {
        Binding(
            get: { editorDraft != nil },
            set: { if !$0 { editorDraft = nil } }
        )
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

    private var serverSummaryCard: some View {
        InsetCard(
            cornerRadius: 18,
            contentPadding: 14,
            backgroundColor: Color(.systemBackground),
            strokeOpacity: 0.04
        ) {
            HStack(alignment: .top, spacing: 12) {
                RemoteServerGlyph(profile: profile, size: 42, cornerRadius: 12, iconFont: .title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(profile.providerDisplayTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(profile.providerKind.tintColor)
                        .lineLimit(1)
                }
            }

            SummaryMetricGroup(
                metrics: summaryMetrics,
                style: .compactValue,
                horizontalSpacing: 8,
                verticalSpacing: 8
            )

            RemoteInlineMetadataLine(
                items: summaryMetadataItems,
                horizontalSpacing: 8,
                verticalSpacing: 4
            )
        }
    }

    private var quickAccessSection: some View {
        Section("Quick Access") {
            ForEach(quickAccessItems) { item in
                Button {
                    navigationRequest = item.navigationRequest
                } label: {
                    RemoteInsetListRowCard {
                        RemoteServerDetailShortcutRow(item: item)
                    }
                }
                .buttonStyle(.plain)
                .insetCardListRow(horizontalInset: RemoteServerDetailLayoutMetrics.horizontalInset)
            }
        }
    }

    private var recentComicsSection: some View {
        Section("Recent Comics") {
            if recentSessions.isEmpty {
                ContentUnavailableView(
                    "No Browsing History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Open a comic from this remote server and it will appear here.")
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
                                    for: session.comicFileReference
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteRecentSession(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
        browserEntryIsRoot ? "Browse Remote Library" : "Continue Browsing"
    }

    private var browserEntryDisplayText: String {
        browserEntryRawPath.isEmpty ? "/" : browserEntryRawPath
    }

    private var summaryMetrics: [SummaryMetricItem] {
        [
            SummaryMetricItem(
                title: "Saved",
                value: "\(savedFolderCount)",
                tint: .teal
            ),
            SummaryMetricItem(
                title: "Offline",
                value: "\(offlineCopyCount)",
                tint: .green
            ),
            SummaryMetricItem(
                title: "Recent",
                value: "\(recentHistoryCount)",
                tint: .orange
            )
        ]
    }

    private var summaryMetadataItems: [RemoteInlineMetadataItem] {
        var items = [
            RemoteInlineMetadataItem(
                systemImage: "server.rack",
                text: profile.endpointDisplaySummary,
                tint: .blue
            ),
            RemoteInlineMetadataItem(
                systemImage: "point.3.connected.trianglepath.dotted",
                text: profile.shareDisplaySummary,
                tint: .teal
            )
        ]

        if !profile.username.isEmpty, profile.authenticationMode.requiresUsername {
            items.append(
                RemoteInlineMetadataItem(
                    systemImage: "person.text.rectangle",
                    text: profile.username,
                    tint: .secondary
                )
            )
        }

        return items
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
                    subtitle: "Open shortcuts for this server.",
                    systemImage: "star",
                    tint: .teal,
                    badgeTitle: "\(savedFolderCount)",
                    navigationRequest: .savedFolders(profile)
                )
            )
        }

        if offlineCopyCount > 0 {
            items.append(
                RemoteServerDetailShortcutItem(
                    id: "offline-shelf",
                    title: "Offline Shelf",
                    subtitle: "Open comics kept on this device.",
                    systemImage: "arrow.down.circle",
                    tint: .green,
                    badgeTitle: "\(offlineCopyCount)",
                    navigationRequest: .offlineShelf(profile)
                )
            )
        }

        return items
    }

    @ViewBuilder
    private var remoteServerActionMenuContent: some View {
        Button {
            editorDraft = viewModel.makeEditDraft(for: profile)
        } label: {
            Label("Edit Server", systemImage: "square.and.pencil")
        }

        if savedFolderCount > 0 {
            Button {
                navigationRequest = .savedFolders(profile)
            } label: {
                Label(
                    savedFolderCount == 1 ? "Open Saved Folder" : "Open Saved Folders",
                    systemImage: "star"
                )
            }
        }

        if offlineCopyCount > 0 {
            Button {
                navigationRequest = .offlineShelf(profile)
            } label: {
                Label(
                    offlineCopyCount == 1 ? "Open Offline Copy" : "Open Offline Shelf",
                    systemImage: "arrow.down.circle"
                )
            }
        }

        if recentHistoryCount > 0 {
            Button(role: .destructive) {
                viewModel.clearRecentHistory(for: profile)
                refreshDetailState(forceReload: true)
            } label: {
                Label("Clear Browsing History", systemImage: "clock.arrow.circlepath")
            }
        }

        if !viewModel.cacheSummary(for: profile).isEmpty {
            Button(role: .destructive) {
                viewModel.clearCache(for: profile)
                refreshDetailState(forceReload: true)
            } label: {
                Label("Clear Download Cache", systemImage: "trash")
            }
        }

        Button(role: .destructive) {
            viewModel.delete(profile)
            dismiss()
        } label: {
            Label("Delete Server", systemImage: "trash")
        }
    }

    private func recentSessionActionMenu(
        for session: RemoteComicReadingSession
    ) -> some View {
        Menu {
            Button(role: .destructive) {
                deleteRecentSession(session)
            } label: {
                Label("Delete History Entry", systemImage: "trash")
            }
        } label: {
            PersistentRowActionButtonLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage \(session.displayName)")
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
    var badgeTitle: String? = nil
    let navigationRequest: RemoteServerDetailNavigationRequest
}

private struct RemoteServerDetailShortcutRow: View {
    let item: RemoteServerDetailShortcutItem

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: item.systemImage)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let badgeTitle = item.badgeTitle {
                StatusBadge(title: badgeTitle, tint: item.tint)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
