import SwiftUI

private enum BrowseLayoutMetrics {}

struct BrowseHomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let dependencies: AppDependencies

    @StateObject private var viewModel: RemoteServerListViewModel
    @State private var editorDraft: RemoteServerEditorDraft?
    @State private var pendingDeletionProfile: RemoteServerProfile?
    @State private var navigationRequest: BrowseHomeNavigationRequest?
    @State private var splitSelection: BrowseHomeSplitSelection?
    @State private var splitSyncTask: Task<Void, Never>?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
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
        Group {
            if usesSplitViewLayout {
                splitViewLayout
            } else {
                compactLayout
            }
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .onAppear {
            debounceSplitSync()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: displayedProfiles.map(\.id)) { _, _ in
            debounceSplitSync()
        }
        .onChange(of: quickAccessItems.map(\.id)) { _, _ in
            debounceSplitSync()
        }
        .sheet(isPresented: serverEditorPresented) {
            if let draft = editorDraft {
                remoteServerEditor(for: draft)
            }
        }
        .alert(item: $viewModel.alert) { alert in
            makeRemoteAlert(for: alert)
        }
        .confirmationDialog(
            "Delete Server?",
            isPresented: Binding(
                get: { pendingDeletionProfile != nil },
                set: { if !$0 { pendingDeletionProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletionProfile {
                Button("Delete \(pendingDeletionProfile.name)", role: .destructive) {
                    viewModel.delete(pendingDeletionProfile)
                    self.pendingDeletionProfile = nil
                    synchronizeSplitSelection()
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionProfile = nil
            }
        } message: {
            if let pendingDeletionProfile {
                Text("This removes \(pendingDeletionProfile.name) and clears its local offline data on this device.")
            }
        }
    }

    private var usesSplitViewLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var compactLayout: some View {
        NavigationStack {
            compactContent
                .navigationTitle("浏览")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    addServerToolbarItem
                }
                .refreshable {
                    viewModel.load()
                }
                .navigationDestination(item: $navigationRequest) { request in
                    navigationDestination(for: request)
                }
        }
    }

    private var compactContent: some View {
        Group {
            if displayedProfiles.isEmpty && !showsQuickAccess {
                BrowseHomeEmptyState(onAddServer: presentCreateServerSheet)
            } else {
                List {
                    serversSection

                    if showsQuickAccess {
                        quickAccessSection
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var splitViewLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if displayedProfiles.isEmpty && !showsQuickAccess {
                    BrowseHomeEmptyState(onAddServer: presentCreateServerSheet)
                        .background(Color.surfaceGrouped)
                } else {
                    List(selection: $splitSelection) {
                        splitServersSection

                        if showsQuickAccess {
                            splitQuickAccessSection
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("浏览")
            .toolbar {
                addServerToolbarItem
            }
            .refreshable {
                viewModel.load()
            }
        } detail: {
            NavigationStack {
                if let splitSelection {
                    splitDetailDestination(for: splitSelection)
                } else {
                    BrowseHomeDetailPlaceholder(
                        hasServers: !displayedProfiles.isEmpty,
                        onAddServer: presentCreateServerSheet
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Servers Section

    @ViewBuilder
    private var serversSection: some View {
        Section {
            ForEach(displayedProfiles) { profile in
                Button {
                    navigationRequest = .serverDetail(profile)
                } label: {
                    BrowseHomeServerRow(profile: profile)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editorDraft = viewModel.makeEditDraft(for: profile)
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        editorDraft = viewModel.makeEditDraft(for: profile)
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Servers")
        }
    }

    @ViewBuilder
    private var splitServersSection: some View {
        Section("Servers") {
            ForEach(displayedProfiles) { profile in
                Button {
                    splitSelection = .server(profile.id)
                } label: {
                    BrowseHomeServerRow(profile: profile, showsDisclosureIndicator: false)
                }
                .buttonStyle(.plain)
                .tag(BrowseHomeSplitSelection.server(profile.id) as BrowseHomeSplitSelection?)
                .contextMenu {
                    Button {
                        editorDraft = viewModel.makeEditDraft(for: profile)
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pendingDeletionProfile = profile
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Quick Access Section

    private var quickAccessSection: some View {
        Section {
            ForEach(quickAccessItems) { item in
                Button {
                    navigationRequest = item.navigationRequest
                } label: {
                    BrowseHomeQuickAccessRow(item: item)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Quick Access")
        }
    }

    private var splitQuickAccessSection: some View {
        Section("Quick Access") {
            ForEach(quickAccessItems) { item in
                Button {
                    splitSelection = item.splitSelection
                } label: {
                    BrowseHomeQuickAccessRow(item: item, showsDisclosureIndicator: false)
                }
                .buttonStyle(.plain)
                .tag(item.splitSelection as BrowseHomeSplitSelection?)
            }
        }
    }

    // MARK: - Data

    private var displayedProfiles: [RemoteServerProfile] {
        viewModel.profiles.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var totalSavedFolderCount: Int {
        viewModel.profiles.reduce(0) { $0 + viewModel.shortcutCount(for: $1) }
    }

    private var totalOfflineCopyCount: Int {
        viewModel.profiles.reduce(0) { $0 + viewModel.cacheSummary(for: $1).fileCount }
    }

    private var showsQuickAccess: Bool {
        !quickAccessItems.isEmpty
    }

    private var quickAccessItems: [BrowseHomeShortcutItem] {
        var items = [BrowseHomeShortcutItem]()

        if totalSavedFolderCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "saved-folders",
                    title: "Saved Folders",
                    subtitle: "\(totalSavedFolderCount) bookmarked",
                    systemImage: "star.fill",
                    tint: .teal,
                    badgeCount: totalSavedFolderCount,
                    navigationRequest: .savedFolders
                )
            )
        }

        if totalOfflineCopyCount > 0 {
            items.append(
                BrowseHomeShortcutItem(
                    id: "offline-shelf",
                    title: "Offline Shelf",
                    subtitle: "\(totalOfflineCopyCount) cached",
                    systemImage: "arrow.down.circle.fill",
                    tint: .green,
                    badgeCount: totalOfflineCopyCount,
                    navigationRequest: .offlineShelf
                )
            )
        }

        return items
    }

    @ToolbarContentBuilder
    private var addServerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: presentCreateServerSheet) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Remote Server")
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
                synchronizeSplitSelection()
            }
            return alertState
        }
        .id(draft.id)
    }

    @ViewBuilder
    private func navigationDestination(for request: BrowseHomeNavigationRequest) -> some View {
        switch request {
        case .serverDetail(let profile):
            RemoteServerDetailView(
                profile: profile,
                dependencies: dependencies
            )
        case .savedFolders:
            SavedRemoteFoldersView(dependencies: dependencies)
        case .offlineShelf:
            RemoteOfflineShelfView(dependencies: dependencies)
        }
    }

    @ViewBuilder
    private func splitDetailDestination(for selection: BrowseHomeSplitSelection) -> some View {
        switch selection {
        case .server(let profileID):
            if let profile = displayedProfiles.first(where: { $0.id == profileID }) {
                RemoteServerDetailView(
                    profile: profile,
                    dependencies: dependencies
                )
            } else {
                ContentUnavailableView(
                    "Server Unavailable",
                    systemImage: "server.rack",
                    description: Text("The selected server is no longer available on this device.")
                )
            }
        case .savedFolders:
            SavedRemoteFoldersView(dependencies: dependencies)
        case .offlineShelf:
            RemoteOfflineShelfView(dependencies: dependencies)
        }
    }

    private func presentCreateServerSheet() {
        editorDraft = viewModel.makeCreateDraft()
    }

    private func debounceSplitSync() {
        splitSyncTask?.cancel()
        splitSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            synchronizeSplitSelection()
        }
    }

    private func synchronizeSplitSelection() {
        guard usesSplitViewLayout else {
            splitSelection = nil
            return
        }

        let validSelections = Set(
            displayedProfiles.map { BrowseHomeSplitSelection.server($0.id) }
            + quickAccessItems.map(\.splitSelection)
        )

        if let splitSelection, validSelections.contains(splitSelection) {
            return
        }

        splitSelection = displayedProfiles.first.map { .server($0.id) }
            ?? quickAccessItems.first?.splitSelection
    }
}

// MARK: - Navigation

private enum BrowseHomeNavigationRequest: Identifiable, Hashable {
    case serverDetail(RemoteServerProfile)
    case savedFolders
    case offlineShelf

    var id: String {
        switch self {
        case .serverDetail(let profile):
            return "server:\(profile.id.uuidString)"
        case .savedFolders:
            return "saved-folders"
        case .offlineShelf:
            return "offline-shelf"
        }
    }
}

private enum BrowseHomeSplitSelection: Hashable {
    case server(UUID)
    case savedFolders
    case offlineShelf
}

// MARK: - Supporting Types

private struct BrowseHomeShortcutItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let badgeCount: Int
    let navigationRequest: BrowseHomeNavigationRequest

    var splitSelection: BrowseHomeSplitSelection {
        switch navigationRequest {
        case .serverDetail(let profile):
            return .server(profile.id)
        case .savedFolders:
            return .savedFolders
        case .offlineShelf:
            return .offlineShelf
        }
    }
}

// MARK: - Server Row

private struct BrowseHomeServerRow: View {
    let profile: RemoteServerProfile
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(
                systemImage: protocolSystemImage,
                tint: profile.providerKind.tintColor
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(profile.name)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xxs) {
                    Text(profile.endpointDisplaySummary)
                        .lineLimit(1)

                    Text("·")

                    Text(profile.providerKind.title)
                }
                .font(AppFont.footnote())
                .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }

    private var protocolSystemImage: String {
        switch profile.providerKind {
        case .smb:
            return "externaldrive.connected.to.line.below"
        case .webdav:
            return "globe"
        }
    }
}

// MARK: - Quick Access Row

private struct BrowseHomeQuickAccessRow: View {
    let item: BrowseHomeShortcutItem
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ListIconBadge(systemImage: item.systemImage, tint: item.tint)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(item.title)
                    .font(AppFont.body())
                    .foregroundStyle(Color.textPrimary)

                Text(item.subtitle)
                    .font(AppFont.footnote())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: Spacing.xs)

            Text("\(item.badgeCount)")
                .font(AppFont.subheadline())
                .foregroundStyle(Color.textSecondary)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption2(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

private struct BrowseHomeEmptyState: View {
    let onAddServer: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "server.rack",
            title: "No Servers",
            description: "Add a remote server to browse your comic library over the network.",
            actionTitle: "Add Server",
            action: onAddServer
        )
    }
}

private struct BrowseHomeDetailPlaceholder: View {
    let hasServers: Bool
    let onAddServer: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                hasServers ? "Select a Server" : "Add a Server",
                systemImage: "server.rack"
            )
        } description: {
            Text(
                hasServers
                    ? "Choose a remote server or quick access shortcut from the sidebar."
                    : "Add a remote server to start browsing comics over your network."
            )
        } actions: {
            if !hasServers {
                Button(action: onAddServer) {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceGrouped)
    }
}
